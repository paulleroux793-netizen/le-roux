# CSV (opens directly in Excel) for a TransactionReport — Elixir "Transaction Analysis" style:
# per-dentist TURNOVER broken out by charge code, then PAYMENTS received to accounts.
require "csv"

class TransactionReportCsv
  def self.render(report) = new(report).render

  def initialize(report) = (@r = report)

  def render
    r = @r
    CSV.generate do |csv|
      csv << ["Dr Chalita le Roux Inc — Transaction analysis", r.label]
      csv << ["Period", r.period, "Generated", Time.current.strftime("%Y-%m-%d %H:%M")]
      csv << []

      # ── Turnover by dentist, line by line (every charge code) ─────────────
      csv << ["TURNOVER BY DENTIST (charge codes billed)"]
      r.turnover_by_provider.each do |provider, rows|
        csv << []
        csv << ["Provider", provider]
        csv << ["Date", "Patient", "Tooth", "Account", "Code", "Description", "Patient due (R)", "Scheme due (R)", "Line total (R)", "Units"]
        rows.each do |l|
          csv << [
            l.date&.strftime("%Y-%m-%d"), l.patient, l.tooth, l.account_code, l.code, l.description,
            money(l.self_cents), money(l.medical_cents), money(l.total_cents), l.qty
          ]
        end
        csv << ["", "", "", "", "", "PROVIDER TOTAL", "", "", money(rows.sum(&:total_cents)), rows.sum(&:qty)]
      end
      csv << []
      csv << ["", "", "", "", "", "TOTAL TURNOVER", "", "", money(r.turnover_total_cents)]
      csv << []

      # ── Payments received to accounts ─────────────────────────────────────
      csv << ["PAYMENTS RECEIVED (to accounts)"]
      csv << ["Date/Time", "Patient / Account", "Method", "Type", "Reference", "Amount (R)"]
      r.rows.each do |row|
        csv << [row.at.strftime("%Y-%m-%d %H:%M"), row.party, row.method, row.kind, row.reference, money(row.amount_cents)]
      end
      csv << ["Totals by method"]
      r.totals_by_method.each { |m, c| csv << [m.capitalize, "", "", "", "", money(c)] }
      csv << ["TOTAL RECEIVED", "", "", "", "", money(r.total_cents)]
      csv << ["Transactions", r.count]
    end
  end

  private

  def money(cents) = format("%.2f", cents.to_i / 100.0)
end
