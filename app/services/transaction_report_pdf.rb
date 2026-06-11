# Pure-Prawn PDF for a TransactionReport — Elixir "Transaction Analysis" style: per-dentist
# turnover broken out by charge code (auto-paginates), then payments received to accounts.
require "prawn"
require "prawn/table"

class TransactionReportPdf
  Prawn::Fonts::AFM.hide_m17n_warning = true

  def self.render(report) = new(report).render

  def initialize(report) = (@r = report)

  def render
    r = @r
    practice_name = (PracticeBillingProfile.current&.practice_name rescue nil).presence || "Dr Chalita le Roux Inc"
    Prawn::Document.new(page_size: "A4", margin: 30) do |pdf|
      pdf.text practice_name, size: 15, style: :bold
      pdf.text "Transaction analysis - #{r.label}", size: 11
      pdf.text "Generated #{Time.current.strftime('%d %b %Y %H:%M')}", size: 8, color: "888888"
      pdf.move_down 10

      # ── Turnover by dentist ───────────────────────────────────────────────
      pdf.text "Turnover by dentist (charge codes billed)", size: 12, style: :bold
      pdf.move_down 4
      if r.turnover_by_provider.empty?
        pdf.text "No charge codes billed in this period.", size: 9, style: :italic, color: "888888"
      else
        r.turnover_by_provider.each do |provider, rows|
          pdf.move_down 6
          pdf.text provider, size: 10, style: :bold, color: "1f6f54"
          data = [["Date", "Patient", "Tooth", "Code", "Description", "Units", "Total"]]
          rows.each do |l|
            data << [
              l.date&.strftime("%d/%m/%y"), ascii(l.patient).to_s[0, 26], l.tooth.to_s, l.code.to_s,
              ascii(l.description).to_s[0, 30], l.qty.to_s, "R %.2f" % (l.total_cents / 100.0)
            ]
          end
          data << ["", "", "", "", "PROVIDER TOTAL", rows.sum(&:qty).to_s, "R %.2f" % (rows.sum(&:total_cents) / 100.0)]
          pdf.table(data, header: true, width: pdf.bounds.width,
                    column_widths: { 0 => 50, 2 => 32, 3 => 42, 5 => 36, 6 => 66 },
                    cell_style: { size: 7, padding: 3 }) do |t|
            t.row(0).font_style = :bold
            t.row(0).background_color = "eeeeee"
            t.row(-1).font_style = :bold
            t.row(-1).background_color = "f3f3f3"
            t.columns(5..6).align = :right
          end
        end
        pdf.move_down 6
        pdf.text "TOTAL TURNOVER: R %.2f" % (r.turnover_total_cents / 100.0), size: 11, style: :bold
      end

      # ── Payments received to accounts ─────────────────────────────────────
      pdf.move_down 16
      pdf.text "Payments received (to accounts)", size: 12, style: :bold
      pdf.move_down 4
      if r.rows.any?
        pdata = [["Date/Time", "Patient / Account", "Method", "Reference", "Amount"]]
        r.rows.each do |row|
          pdata << [row.at.strftime("%d/%m %H:%M"), ascii(row.party).to_s[0, 30], row.method,
                    ascii(row.reference).to_s[0, 18], "R %.2f" % (row.amount_cents / 100.0)]
        end
        pdf.table(pdata, header: true, width: pdf.bounds.width,
                  cell_style: { size: 7, padding: 3 }) do |t|
          t.row(0).font_style = :bold
          t.row(0).background_color = "eeeeee"
          t.column(4).align = :right
        end
      else
        pdf.text "No payments received in this period.", size: 9, style: :italic, color: "888888"
      end
      pdf.move_down 8
      tdata = r.totals_by_method.map { |m, c| [m.capitalize, "R %.2f" % (c / 100.0)] }
      tdata << ["TOTAL RECEIVED", "R %.2f" % (r.total_cents / 100.0)]
      pdf.table(tdata, width: 240, cell_style: { size: 9, padding: 4 }) do |t|
        t.row(-1).font_style = :bold
        t.row(-1).background_color = "f3f3f3"
        t.column(1).align = :right
      end
    end.render
  end

  private

  # Prawn's built-in fonts only do Latin-1; strip anything outside it so exotic chars
  # can't garble or warn.
  def ascii(str)
    str.to_s.unicode_normalize(:nfkd).chars.select { |c| c.ord < 256 }.join
  end
end
