# DocumentPdf — Prawn-based PDF renderer for invoices and estimates.
# P9.5. Pure-Ruby; no native binary dependency.
#
# The on-screen "Print / PDF" button still uses the browser for
# pixel-perfect WYSIWYG against the React print view. This service is
# the PROGRAMMATIC path — used by the .pdf endpoint and (in a follow-up)
# the WhatsApp send. Layout is conservative A4: header → patient → lines
# table → totals → footer.

require "prawn"
require "prawn/table"

class DocumentPdf
  # Build a PDF for an Invoice. Returns a binary String.
  def self.invoice(invoice)
    new(:invoice, invoice).render
  end

  # Build a PDF for an Estimate. Returns a binary String.
  def self.estimate(estimate)
    new(:estimate, estimate).render
  end

  def initialize(kind, document)
    @kind = kind          # :invoice | :estimate
    @doc  = document
    @practice = PracticeBillingProfile.current
  end

  def render
    pdf = Prawn::Document.new(page_size: "A4", margin: [ 40, 40, 40, 40 ])

    @pdf = pdf
    draw_header
    draw_patient_block
    draw_lines
    draw_totals
    draw_footer

    pdf.render
  end

  private

  attr_reader :pdf, :doc, :practice

  # The built-in PDF font is Windows-1252 (WinAnsi). Patient names / line text
  # with characters outside it (ā, Greek, Cyrillic, emoji, …) would otherwise
  # raise Prawn::Errors::IncompatibleStringEncoding and 500 the whole PDF.
  # Keep Latin-1 accents (é, ë, ô — common SA names render unchanged); for the
  # rest, transliterate to ASCII where possible (ā→a) and drop what can't map.
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

  # ── Header: practice name + document number/date ────────────────────
  def draw_header
    pdf.bounding_box([ 0, pdf.cursor ], width: pdf.bounds.width) do
      pdf.font_size 18
      pdf.fill_color "9A7521"           # Brand gold from logo
      pdf.text practice.practice_name.to_s, style: :bold
      pdf.fill_color "000000"
      pdf.font_size 9
      pdf.text practice.address.to_s if practice.address.present?
      pdf.text "#{practice.phone} · #{practice.email}", style: :italic if practice.phone.present? || practice.email.present?
      pdf.text "HPCSA: #{practice.hpcsa_number}  ·  Practice no: #{practice.bhf_practice_number.presence || '—'}  ·  VAT: #{practice.vat_number.presence || 'Not registered'}"
      # Treating-provider HPCSA — medical aids need the specific dentist's number on
      # the claim (Chalita vs Eliska), not just the practice number. Reuses the
      # StatementPdf lookup so invoice/estimate and statement stay consistent.
      if doc.respond_to?(:provider_name) && doc.provider_name.present?
        prov_hpcsa = StatementPdf::PROVIDER_HPCSA[doc.provider_name] || practice.hpcsa_number
        pdf.text "Treating provider: #{doc.provider_name.titleize}  ·  HPCSA: #{prov_hpcsa}", style: :bold
      end
    end

    pdf.move_down 6
    pdf.stroke_color "DDDDDD"
    pdf.stroke_horizontal_rule
    pdf.move_down 10

    pdf.font_size 14
    pdf.fill_color "9A7521"
    pdf.text @kind == :invoice ? "TAX INVOICE" : "TREATMENT ESTIMATE", style: :bold, align: :right
    pdf.fill_color "000000"

    pdf.font_size 9
    pdf.text "Number: #{document_number}", align: :right
    pdf.text "Date: #{document_date_str}", align: :right
    if @kind == :estimate && doc.valid_until
      pdf.text "Valid until: #{doc.valid_until.strftime('%-d %b %Y')}", align: :right
    end
    pdf.move_down 16
  end

  # ── Patient + scheme block ──────────────────────────────────────────
  def draw_patient_block
    patient = doc.patient
    membership = patient.scheme_memberships.first
    scheme_name = winansi(membership&.medical_scheme&.name || "— Private —")
    # Dependant code lives on the per-patient join (SchemeMembershipPatient).
    dep = membership && SchemeMembershipPatient.find_by(scheme_membership_id: membership.id, patient_id: patient.id)&.dependant_code

    rows = [
      [ "Patient",     winansi(patient.full_name) ],
      [ "Phone",       patient.display_phone.to_s ],
      [ "Medical aid", scheme_name + (membership ? " · Member #{membership.member_number}#{dep.present? ? " · Dependant #{dep}" : ''}" : "") ],
    ]
    rows << [ "Treating provider", winansi(doc.provider_name) ] if doc.try(:provider_name).present?

    pdf.table(rows, cell_style: { borders: [], padding: [ 2, 6, 2, 0 ], size: 10 }) do
      column(0).font_style = :bold
      column(0).text_color = "707070"
      column(0).width = 80
    end
    pdf.move_down 12
  end

  # ── Lines table ─────────────────────────────────────────────────────
  def draw_lines
    pdf.font_size 9

    if @kind == :estimate && lines_by_visit.size > 1
      lines_by_visit.each do |visit, visit_lines|
        pdf.fill_color "9A7521"
        pdf.text "VISIT #{visit}", style: :bold, size: 10
        pdf.fill_color "000000"
        pdf.move_down 3
        draw_line_table(visit_lines)
        pdf.move_down 8
      end
    else
      draw_line_table(lines)
    end
  end

  def draw_line_table(line_list)
    header = [ [ "Code", "Description", "Tooth", "Medical", "Self", "Amount" ] ]
    rows = line_list.map do |l|
      desc = winansi(l.description.to_s)
      desc += "\nICD-10: #{l.icd10_code}" if l.icd10_code.present?
      [
        winansi(l.code.to_s),
        desc,
        l.tooth_number.to_s.presence || "—",
        money(l.medical_cents),
        money(l.self_cents),
        money(l.line_total_cents),
      ]
    end
    rows = [ [ "(no lines)", "", "", "", "", "" ] ] if rows.empty?

    pdf.table(header + rows,
              header: true,
              cell_style: { borders: [ :bottom ], border_color: "EEEEEE", padding: [ 5, 4, 5, 4 ], size: 9 },
              column_widths: { 0 => 50, 2 => 40, 3 => 65, 4 => 65, 5 => 70 }) do
      row(0).background_color = "F5F0E5"
      row(0).font_style = :bold
      row(0).text_color = "9A7521"
      row(0).borders = [ :bottom ]
      columns(3..5).align = :right
      column(2).align = :center
    end
  end

  # ── Totals block ────────────────────────────────────────────────────
  def draw_totals
    pdf.move_down 12
    box_x = pdf.bounds.width - 240

    pdf.bounding_box([ box_x, pdf.cursor ], width: 240) do
      total_rows = [
        [ "Subtotal",                       money(doc.subtotal_cents) ],
        [ "VAT",                            money(doc.vat_cents) ],
        [ "Medical (claim from your aid)",  money(doc.medical_total * 100) ],
        [ "Self (you pay)",                 money(doc.self_total * 100) ],
        [ @kind == :invoice ? "TOTAL DUE" : "TOTAL ESTIMATE", money(doc.total_cents) ]
      ]
      pdf.font_size 9
      pdf.table(total_rows, cell_style: { borders: [], padding: [ 3, 6, 3, 6 ], size: 9 }) do
        column(1).align = :right
        column(1).font_style = :bold
        row(-1).background_color = "F5F0E5"
        row(-1).font_style = :bold
        row(-1).size = 11
      end
    end
  end

  # ── Footer: payment + compliance ───────────────────────────────────
  def draw_footer
    pdf.move_down 20
    pdf.stroke_color "DDDDDD"
    pdf.stroke_horizontal_rule
    pdf.move_down 8

    pdf.font_size 8
    pdf.fill_color "707070"

    pdf.text "Payment / banking", style: :bold, color: "000000"
    pdf.text [
      practice.bank_name,
      practice.bank_account_name,
      "Acc: #{practice.bank_account_number}",
      "Branch: #{practice.bank_branch_code}"
    ].compact.reject(&:blank?).join(" · ")

    pdf.move_down 8

    if @kind == :estimate
      pdf.fill_color "9A7521"
      pdf.text "ESTIMATE VALID FOR 14 DAYS", style: :bold
      pdf.fill_color "707070"
      pdf.text "This is an estimate of planned treatment, not a final account. Actual fees may vary " \
               "depending on what is clinically required on the day. You may submit the final invoice to " \
               "your medical aid to claim back."
    else
      pdf.fill_color "9A7521"
      pdf.text "PAYMENT TERMS: ON RECEIPT", style: :bold
      pdf.fill_color "707070"
      pdf.text "This is a patient-pay invoice. We do not claim from medical aid on your behalf. " \
               "Submit this invoice to your scheme for reimbursement."
    end

    pdf.move_down 10
    pdf.text "Generated #{Time.current.strftime('%-d %b %Y at %H:%M')} · Page <page> of <total>", size: 7, color: "AAAAAA"
  end

  # ── Helpers ─────────────────────────────────────────────────────────
  def document_number
    @kind == :invoice ? doc.invoice_number : doc.estimate_number
  end

  def document_date_str
    date = @kind == :invoice ? doc.invoice_date : doc.created_at.to_date
    date.strftime("%-d %b %Y")
  end

  def lines
    @kind == :invoice ? doc.invoice_lines : doc.estimate_lines
  end

  def lines_by_visit
    return { 1 => lines } if @kind == :invoice
    doc.lines_by_visit
  end

  def money(cents)
    "R#{format('%.2f', cents.to_i / 100.0)}"
  end
end
