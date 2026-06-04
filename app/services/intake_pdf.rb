# IntakePdf — the printable intake pack reception prints when the patient arrives.
# Pure-Ruby Prawn (no native binary), same brand styling as DocumentPdf.
#
# It renders the patient's COMPLETED intake forms, pre-filled with the answers they
# typed on their phone, and leaves BLANK signature + initial blocks for the wet
# signature on arrival (print-and-sign workflow — nothing is signed digitally).
#
#   IntakePdf.new(patient).render   # => binary PDF String

require "prawn"

class IntakePdf
  GOLD = "9A7521"
  GREY = "707070"
  LINE = "E8E1D4"
  LOGO_PATH = Rails.root.join("public/brand/logo.png").freeze
  FONT_DIR  = Rails.root.join("vendor/fonts").freeze

  # Canonical practice details (match the printed patient-file insert). Pulled from
  # PracticeBillingProfile where available so they track the dashboard settings,
  # with the printed-form values as the fallback.
  REGISTRATION   = "B.Ch.D (Pret) (Cum Laude)   ·   Practice no. 0992801"
  ADDRESS_LINE   = "Unit 2, Amorosa Office Park, 68 Lawrence Road, Amorosa, Roodepoort, 2040"
  CONTACT_LINE   = "Tel 011 568 8255  ·  071 884 3204  ·  info@drchalitaleroux.co.za"
  BANKING_LINE   = "Dr Chalita Le Roux Inc  ·  Investec Bank Limited  ·  Acc 10013494325  ·  Branch 580105"

  # The payment & cancellation policy letter from the printed patient-file insert.
  # PRINT-ONLY: it is NOT part of the online questionnaire — it is appended to the
  # printed pack so the patient signs + initials it on arrival, acknowledging that
  # the practice does not claim from medical aid (patient pays, then claims back).
  POLICY_PARAGRAPHS = [
    "This practice is contracted out of medical aid tariffs and requires IMMEDIATE payment for all services rendered.",
    "You are kindly requested to settle your account straight after consultation.",
    "Credit / debit cards, masterpass and cash accepted.",
    "Settled accounts will be emailed to you in order for you to claim back from your medical aid.",
    "Unfortunately, we do not allow EFTs or month-end payments.",
    "Pensioners, please enquire for special benefits."
  ].freeze
  CANCELLATION_TEXT =
    "Please reschedule or cancel your appointment 24 hours before your appointment. Failing this, you " \
    "will be charged an appointment-not-kept fee should we not be able to fill your slot.".freeze
  POLICY_ACKNOWLEDGEMENT =
    "I have read and understood the above. I understand that this practice does NOT claim from medical " \
    "aid — I pay the practice directly for all services and claim back from my medical scheme myself.".freeze

  def initialize(patient)
    @patient = patient
    @practice = PracticeBillingProfile.current
  end

  def render
    # Bottom margin reserves space for the footer (drawn after content, per page).
    @pdf = Prawn::Document.new(page_size: "A4", margin: [ 36, 40, 92, 40 ])
    setup_font

    # Page 1 is ALWAYS the payment & cancellation policy the patient signs on arrival.
    draw_payment_policy_page

    completed_submissions.each do |submission|
      pdf.start_new_page
      draw_practice_header
      draw_form(submission)
      draw_signature_block
    end

    draw_footers # after all content — go_to_page + canvas (NOT repeat, which corrupts state)
    pdf.render
  end

  # The print-only policy page: practice letter + a bottom-right sign/initial block.
  def draw_payment_policy_page
    draw_practice_header

    pdf.fill_color GOLD
    pdf.font_size 13
    pdf.text "Payment & Cancellation Policy", style: :bold
    pdf.fill_color "000000"
    pdf.move_down 10

    pdf.font_size 10
    pdf.text "Dear patient,", style: :bold
    pdf.move_down 4
    pdf.text "Please note:"
    pdf.move_down 8

    POLICY_PARAGRAPHS.each do |para|
      pdf.text para
      pdf.move_down 7
    end

    pdf.move_down 4
    pdf.fill_color GOLD
    pdf.text "Cancellations", style: :bold, size: 11
    pdf.fill_color "000000"
    pdf.move_down 4
    pdf.text CANCELLATION_TEXT
    pdf.move_down 14
    pdf.text "Kind regards,"
    pdf.text "Dr Chalita le Roux and team"

    draw_policy_signature
  end

  # Acknowledgement + sign/initial, anchored bottom-RIGHT (per the printed form).
  def draw_policy_signature
    pdf.move_down 26
    pdf.fill_color GREY
    pdf.font_size 9
    pdf.text POLICY_ACKNOWLEDGEMENT
    pdf.fill_color "000000"
    pdf.move_down 22

    pdf.text "Initial: ____________", align: :right
    pdf.move_down 16
    pdf.text "Signature: ______________________________     Date: ____ / ____ / 20____", align: :right
  end

  private

  attr_reader :pdf, :patient, :practice

  # Use the vendored DejaVu Sans (full Unicode). Crucial for live data: a TTF renders
  # unknown glyphs as blank boxes instead of raising. Prawn's built-in Helvetica
  # crashes on ANY character outside Windows-1252 — so a patient typing an emoji or an
  # unusual symbol in a free-text field would otherwise break their whole PDF. Falls
  # back to the built-in font only if the vendored file is somehow missing.
  def setup_font
    regular = FONT_DIR.join("DejaVuSans.ttf")
    return unless File.exist?(regular)

    bold = FONT_DIR.join("DejaVuSans-Bold.ttf")
    bold = regular unless File.exist?(bold)
    pdf.font_families.update("DejaVu" => {
      normal: regular.to_s, bold: bold.to_s, italic: regular.to_s, bold_italic: bold.to_s
    })
    pdf.font "DejaVu"
  end

  # Latest completed submission per intake template, in form order.
  def completed_submissions
    IntakeProcessor::KEYS.filter_map do |key|
      patient.form_submissions.joins(:form_template)
             .where(form_templates: { key: key }, status: "completed")
             .order(:completed_at).last
    end
  end

  # Centered practice logo (the real wordmark) + registration line, matching the
  # top of the printed patient forms. Falls back to a gold text wordmark if the
  # logo asset is missing.
  def draw_practice_header
    if File.exist?(LOGO_PATH)
      pdf.image LOGO_PATH.to_s, width: 200, position: :center
      pdf.move_down 6
    else
      pdf.fill_color GOLD
      pdf.font_size 17
      pdf.text(practice&.practice_name.presence || "Dr Chalita le Roux", style: :bold, align: :center)
      pdf.fill_color GREY
      pdf.font_size 8
      pdf.text "dentist & aesthetic practitioner", align: :center
      pdf.fill_color "000000"
    end

    pdf.fill_color GREY
    pdf.font_size 8
    pdf.text registration_line, align: :center
    pdf.fill_color "000000"

    pdf.move_down 6
    pdf.stroke_color GOLD
    pdf.line_width 1
    pdf.stroke_horizontal_rule
    pdf.line_width 0.5
    pdf.move_down 12
  end

  # Footer on every page — practice address, contact + banking, like the printed
  # form. Drawn AFTER all content by walking the pages with go_to_page + canvas
  # (absolute page coordinates). NOT repeat()+canvas, which corrupts Prawn's
  # graphics-state stack (EmptyGraphicStateStack). The large bottom margin reserves
  # the space so the footer never collides with flowing content.
  def draw_footers
    (1..pdf.page_count).each do |page|
      pdf.go_to_page(page)
      pdf.canvas do
        pdf.bounding_box([ 40, 80 ], width: pdf.bounds.width - 80) do
          pdf.stroke_color LINE
          pdf.stroke_horizontal_rule
          pdf.move_down 5
          pdf.fill_color GREY
          pdf.font_size 7
          pdf.text address_line, align: :center
          pdf.text contact_line, align: :center
          pdf.text banking_line, align: :center
          pdf.fill_color "000000"
        end
      end
    end
  end

  def registration_line
    hpcsa = practice&.hpcsa_number.presence
    bhf   = practice&.bhf_practice_number.presence || "0992801"
    base  = "B.Ch.D (Pret) (Cum Laude)   ·   Practice no. #{bhf}"
    hpcsa ? "#{base}   ·   HPCSA #{hpcsa}" : base
  end

  def address_line
    practice&.address.presence || ADDRESS_LINE
  end

  def contact_line
    parts = [ practice&.phone.presence, practice&.email.presence ].compact
    parts.any? ? "Tel #{parts.join('  ·  ')}" : CONTACT_LINE
  end

  def banking_line
    return BANKING_LINE unless practice&.bank_account_number.present?

    [ practice.bank_account_name, practice.bank_name,
      "Acc #{practice.bank_account_number}", "Branch #{practice.bank_branch_code}" ]
      .compact_blank.join("  ·  ")
  end

  def draw_form(submission)
    schema = submission.form_template.schema.deep_stringify_keys
    data = (submission.data || {}).deep_stringify_keys

    pdf.fill_color GOLD
    pdf.font_size 13
    pdf.text submission.form_template.name, style: :bold
    pdf.fill_color "000000"
    pdf.font_size 8
    pdf.fill_color GREY
    pdf.text "Patient: #{patient.full_name}   ·   Completed: #{submission.completed_at&.strftime('%-d %b %Y')}"
    pdf.fill_color "000000"
    pdf.move_down 8

    Array(schema["sections"]).each { |section| draw_section(section, data) }
  end

  def draw_section(section, data)
    pdf.move_down 6
    pdf.fill_color GOLD
    pdf.font_size 10
    pdf.text section["title"].to_s, style: :bold
    pdf.fill_color "000000"
    pdf.move_down 3

    Array(section["fields"]).each do |field|
      next if hidden?(field, data)

      draw_field(field, data[field["key"]])
    end
  end

  def draw_field(field, value)
    case field["type"]
    when "heading"
      # Consent clauses are initialled by hand → leave an initial line.
      pdf.move_down 4
      pdf.font_size 9
      pdf.text "#{field['label']}      Initial: ____________", style: :bold
      pdf.font_size 8
    when "statement"
      pdf.font_size 8
      pdf.fill_color GREY
      pdf.text field["label"].to_s
      pdf.fill_color "000000"
    else
      pdf.font_size 9
      pdf.text "#{field['label']}: #{display_value(field, value)}", inline_format: false
    end
  end

  def display_value(field, value)
    case field["type"]
    when "yesno"
      return "—" if value.nil?
      truthy?(value) ? "Yes" : "No"
    when "checkbox"
      truthy?(value) ? "✓" : "—"
    else
      value.to_s.strip.presence || "____________________"
    end
  end

  def draw_signature_block
    pdf.move_down 18
    pdf.stroke_color "DDDDDD"
    pdf.stroke_horizontal_rule
    pdf.move_down 12
    pdf.font_size 9
    pdf.text "I declare that the information above is correct and that I will make known any changes in my " \
             "health to the treating practitioner. I accept full responsibility for my account. This is a " \
             "legal and binding consent to treatment.", color: GREY
    pdf.move_down 16
    pdf.text "Signed at ___________________________  on ________ / ________ / 20______"
    pdf.move_down 14
    pdf.text "Signature: ______________________________     Name: ______________________________"
  end

  # reveal_when: hide a field in the printout if the controlling answer doesn't match.
  def hidden?(field, data)
    rule = field["reveal_when"]
    return false if rule.blank?

    expected = rule["equals"]
    answer   = data[rule["field"]]
    # For boolean rules compare truthiness (JSON may store "true"/true); else compare directly.
    actual = [ true, false ].include?(expected) ? truthy?(answer) : answer
    actual != expected
  end

  def truthy?(value)
    [ true, "true", "1", "yes", "on" ].include?(value)
  end
end
