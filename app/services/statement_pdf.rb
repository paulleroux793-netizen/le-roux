# StatementPdf — account statement matching the Elixir layout: practice + account
# header boxes, medical-fund reference, transactions grouped by dependent + provider
# (each line "code x qty  description" with Amount / Credit / Due, place-of-service,
# ICD-10), bank details, age analysis (Current/30/60/90/90+), thank-you. Pure Prawn.
require "prawn"
require "prawn/table"

class StatementPdf
  # Provider HPCSA (BHF is the practice number) — from Elixir PROVIDERS.
  PROVIDER_HPCSA = {
    "DR CHALITA LE ROUX" => "DP0118702", "DR ELISKA ROBINSON" => "DP0122343",
    "DR THEO BOTHA" => "DP0126659", "DR ANNEZE ODENDAAL" => "DP0124460",
    "DR ERIC HEYL" => "DP01212452"
  }.freeze

  LOGO_PATH = Rails.root.join("public/brand/logo.png").freeze

  def self.render(account, from:, to:)
    new(account, from, to).render
  end

  def initialize(account, from, to)
    # Defence-in-depth: the controller defaults these, but guard nil here too so a direct
    # caller can never trigger a "beginning_of_day for nil" 500 deep in rendering.
    @account = account
    @from = from || 1.year.ago.to_date
    @to   = to || Date.current
    @practice = PracticeBillingProfile.current
  end

  def render
    @pdf = Prawn::Document.new(page_size: "A4", margin: [ 30, 34, 30, 34 ])
    title_block
    info_boxes
    holder_boxes
    transactions
    balance_due_callout
    bank_details
    age_analysis
    thank_you
    @pdf.render
  end

  private

  def money(c) = "R#{format('%.2f', c.to_i / 100.0)}"
  def dz(d) = d ? d.strftime("%d/%m/%Y") : ""

  # The built-in PDF font is Windows-1252; a name/address with characters outside
  # it (emoji, ā, Greek, Cyrillic) would raise IncompatibleStringEncoding and 500
  # the statement. Keep Latin-1 (é, ë), transliterate the rest to ASCII, drop the
  # unmappable. (Mirror of DocumentPdf#winansi.)
  def winansi(str)
    s = str.to_s
    return s if s.ascii_only?

    s.each_char.map do |ch|
      ch.encode("Windows-1252")
      ch
    rescue Encoding::UndefinedConversionError
      I18n.transliterate(ch, replacement: "")
    end.join
  end
  def bhf = @practice.bhf_practice_number.presence || "0992801"

  def title_block
    # Practice wordmark logo (matches the printed forms / intake PDF). Falls back to
    # the bold practice name if the asset is missing, so the statement never 500s.
    if File.exist?(LOGO_PATH)
      @pdf.image LOGO_PATH.to_s, width: 200, position: :center
      @pdf.move_down 4
    else
      @pdf.font_size(13) { @pdf.text winansi(@practice.practice_name.to_s.upcase), style: :bold, align: :center }
    end
    @pdf.font_size(16) { @pdf.text "STATEMENT", style: :bold_italic, align: :center }
    @pdf.move_down 10
  end

  def info_boxes
    y = @pdf.cursor
    @pdf.bounding_box([ 0, y ], width: 280, height: 70) do
      @pdf.font_size(9) { @pdf.text winansi(@practice.address.to_s) }
    end
    @pdf.bounding_box([ 320, y ], width: @pdf.bounds.width - 320, height: 70) do
      @pdf.table([
        [ "Date:", dz(Date.current) ], [ "Practice:", bhf ],
        [ "Account:", @account.account_code.to_s ], [ "Page:", "1 of 1" ]
      ], cell_style: { borders: [], padding: [ 1, 4, 1, 0 ], size: 9 }) { column(0).font_style = :bold; column(0).width = 60 }
    end
    @pdf.move_down 80
  end

  def holder_boxes
    head = @account.try(:head_patient) || @account.patients.first
    mem  = head&.scheme_memberships&.first
    y = @pdf.cursor
    @pdf.bounding_box([ 0, y ], width: 280, height: 70) do
      @pdf.font_size(10) { @pdf.text winansi(@account.billing_name.presence || head&.full_name.to_s), style: :bold }
      @pdf.font_size(9)  { @pdf.text winansi(@account.try(:address_line1).to_s) }
    end
    @pdf.bounding_box([ 320, y ], width: @pdf.bounds.width - 320, height: 70) do
      @pdf.font_size 9
      @pdf.text "Medical fund reference:"
      @pdf.text(winansi(mem&.medical_scheme&.name.to_s), style: :bold) if mem
      if mem&.member_number.present?
        dep = SchemeMembershipPatient.find_by(scheme_membership_id: mem.id, patient_id: head&.id)&.dependant_code
        @pdf.text("#{mem.member_number}#{dep.present? ? " · Dependant #{dep}" : ''}", style: :bold)
      end
      @pdf.text "Main member identity number:"
      @pdf.text head&.id_number.to_s, style: :bold
      @pdf.text "Practice VAT no.: #{@practice.vat_number}", style: :bold
    end
    @pdf.move_down 80
  end

  def transactions
    rows = [ [ "Date", "Dependent", "Provider", "BHF / Details", "Amount", "Credit", "Due" ] ]
    rows << [ { content: "This statement does not necessarily reflect all due amounts", colspan: 7 } ]

    # Carry the prior balance into a period statement so "Due" reflects cumulative debt.
    if @from && (bf = opening_cents) != 0
      rows << [ { content: "Balance brought forward", colspan: 6, font_style: :bold }, { content: money(bf), font_style: :bold } ]
    end

    invoices.group_by(&:patient_id).each do |_pid, invs|
      pt = invs.first.patient
      rows << [ { content: winansi("#{pt&.full_name&.upcase} C: #{pt&.display_phone}"), colspan: 7, font_style: :bold } ]
      rows << [ { content: winansi("Dependent: #{pt&.first_name&.upcase} / Born: #{dz(pt&.date_of_birth)} / Number: 01"), colspan: 7 } ]
      invs.sort_by(&:invoice_date).each do |inv|
        prov = inv.provider_name.to_s
        rows << [ { content: "#{prov} [BHF: #{bhf} / HPCSA: #{PROVIDER_HPCSA[prov] || '—'}]", colspan: 7, font_style: :bold } ]
        total = inv.total_cents.to_i
        inv.invoice_lines.each do |l|
          amt = l.line_total_cents.to_i
          cr  = total.positive? ? (inv.paid_cents.to_i * amt / total) : 0
          rows << [ dz(inv.invoice_date), "#{pt&.first_name&.upcase}: #{dz(pt&.date_of_birth)}",
                    prov.split.first(2).join(" "), "#{l.code} x#{l.quantity} #{l.description}",
                    money(amt), money(cr), money(amt - cr) ]
          rows << [ { content: "    Place of service: [11]Consulting room#{l.icd10_code.present? ? "   ICD-10: #{l.icd10_code}" : ''}", colspan: 7, size: 7, text_color: "666666" } ]
        end
      end
    end
    payments.each do |p|
      rows << [ dz(p.received_at.to_date), "", "", "Payment received: #{p.method}", "-#{money(p.amount_cents)}", money(0), money(0) ]
    end

    @pdf.font_size 8
    @pdf.table(rows, header: true, width: @pdf.bounds.width,
               cell_style: { borders: [ :bottom ], border_color: "EEEEEE", padding: [ 2, 3, 2, 3 ], size: 8 },
               column_widths: { 0 => 52, 4 => 58, 5 => 58, 6 => 52 }) do
      row(0).background_color = "DDDDDD"; row(0).font_style = :bold
      columns(4..6).align = :right
    end
    @pdf.move_down 10
  end

  def bank_details
    @pdf.font_size 9
    @pdf.text "*** PRACTICE BANK DETAILS ***", style: :bold, align: :center
    @pdf.text "#{@practice.bank_name} : ACCNAME : #{@practice.bank_account_name}", align: :center
    @pdf.text "ACC NO : #{@practice.bank_account_number}, BR CODE : #{@practice.bank_branch_code}", align: :center
    @pdf.move_down 12
  end

  def age_analysis
    buckets = { c: 0, d30: 0, d60: 0, d90: 0, d90p: 0 }
    patient_due = 0; medical_due = 0
    @account.invoices.where(status: %w[open part_paid]).find_each do |inv|
      out = inv.total_cents.to_i - inv.paid_cents.to_i
      next if out <= 0
      patient_due += out
      days = (Date.current - inv.invoice_date.to_date).to_i
      k = days <= 30 ? :c : days <= 60 ? :d30 : days <= 90 ? :d60 : days <= 120 ? :d90 : :d90p
      buckets[k] += out
    end
    payable = buckets.values.sum
    head = [ "Due patient:", "Due medical:", "Current:", "30 days:", "60 days:", "90 days:", "90 day+:", "Payable:" ]
    vals = [ money(patient_due), money(medical_due), money(buckets[:c]), money(buckets[:d30]), money(buckets[:d60]), money(buckets[:d90]), money(buckets[:d90p]), money(payable) ]
    @pdf.font_size 8
    @pdf.table([ head, vals ], width: @pdf.bounds.width, cell_style: { borders: [ :top, :bottom ], border_color: "AAAAAA", padding: [ 3, 3, 3, 3 ], size: 8, align: :right }) do
      row(0).font_style = :italic; row(1).font_style = :bold
    end
    @pdf.move_down 10
  end

  # Total still owed to the practice across all open/part-paid invoices.
  def outstanding_due_cents
    @account.invoices.where(status: %w[open part_paid]).sum { |i| [ i.total_cents.to_i - i.paid_cents.to_i, 0 ].max }
  end

  # Prominent "what you must pay" callout + payment reference (benchmark: the single highest-impact
  # readability win). Brand-compliant: patient pays the practice and self-claims from their aid.
  def balance_due_callout
    due = outstanding_due_cents
    ref = @account.account_code.presence || @account.id.to_s
    @pdf.move_down 4
    @pdf.table([ [ "BALANCE DUE\n(amount you pay the practice)", money(due) ] ], position: :right, width: 270,
      cell_style: { borders: [ :top, :bottom, :left, :right ], border_width: 1.2, border_color: "111111", padding: [ 6, 8, 6, 8 ] }) do
      column(0).font_style = :bold; column(0).size = 9; column(0).align = :left; column(0).valign = :center
      column(1).font_style = :bold; column(1).size = 15; column(1).align = :right; column(1).valign = :center
    end
    @pdf.move_down 3
    @pdf.font_size(8) do
      @pdf.text "Payment reference: #{ref}  ·  please pay by EFT using the bank details below.", align: :right, style: :bold
      @pdf.text "You may submit this statement to your medical aid to claim back where your benefits allow.", align: :right, style: :italic
      @pdf.text "The account holder remains responsible for this account; the practice does not claim from medical aid on your behalf.", align: :right, style: :italic
    end
    @pdf.move_down 8
  end

  def thank_you
    @pdf.font_size(9) { @pdf.text "THANK YOU FOR CHOOSING #{@practice.practice_name.to_s.upcase} FOR YOUR DENTAL NEEDS.", style: :italic }
  end

  def invoices
    @invoices ||= @account.invoices.where(void: false).where.not(status: "written_off")
                          .where(invoice_date: @from..@to).includes(:invoice_lines, :patient).order(:invoice_date).to_a
  end

  def payments
    # Active real money in only — excludes reversed payments and internal credit moves.
    @payments ||= @account.payments.inward.where(received_at: @from.beginning_of_day..@to.end_of_day).order(:received_at).to_a
  end

  # Net account balance accrued BEFORE the statement period (carried in as "brought forward").
  def opening_cents
    @account.invoices.where(void: false).where.not(status: "written_off").where("invoice_date < ?", @from).sum(:total_cents).to_i -
      @account.payments.inward.where("received_at < ?", @from.beginning_of_day).sum(:amount_cents).to_i
  end
end
