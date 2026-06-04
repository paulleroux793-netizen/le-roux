# Sends a patient the WhatsApp intake link.
#
# Creates one pending FormSubmission per active intake template (so the dashboard
# shows the sent→opened→completed lifecycle), mints a signed, 14-day, PII-free link
# for the patient, and sends it as a free-form WhatsApp message. Free-form requires
# the patient to be inside Twilio's 24-hour service window — true right after they
# book via WhatsApp. If an approved template SID is configured we use that instead
# (works outside the window); otherwise we fall back to free-form.
#
#   IntakeDispatch.call(patient)                       # system-initiated
#   IntakeDispatch.call(patient, from_number: "+27…")  # reply on the line they used
class IntakeDispatch
  KEYS = IntakeProcessor::KEYS

  class Error < StandardError; end

  def self.call(patient, from_number: nil)
    new(patient, from_number: from_number).call
  end

  def initialize(patient, from_number: nil)
    @patient = patient
    @from_number = from_number
  end

  def call
    raise Error, "patient has no WhatsApp number" if @patient.phone.blank?

    templates = FormTemplate.active.where(key: KEYS).index_by(&:key)
    missing = KEYS - templates.keys
    raise Error, "intake templates not seeded: #{missing.join(', ')}" if missing.any?

    KEYS.each do |key|
      @patient.form_submissions.create!(form_template: templates[key]).mark_sent!
    end

    link = intake_link
    deliver(link)
    link
  end

  private

  def intake_link
    base = ENV.fetch("BASE_URL").chomp("/")
    token = @patient.signed_id(purpose: :intake, expires_in: 14.days)
    "#{base}/intake/#{token}"
  end

  def deliver(link)
    WhatsappTemplateService.new(from_number: @from_number).send_text(@patient.phone, body(link))
  rescue WhatsappTemplateService::Error => e
    raise Error, "could not send intake link: #{e.message}"
  end

  # Warm, single-CTA, link on its own line (WhatsApp best practice). Emphasises
  # paperless + quick + private — the framing that maximises completion.
  def body(link)
    <<~MSG.strip
      Hi #{@patient.first_name} 👋

      Thank you for booking with Dr Chalita le Roux 🦷 To keep things paperless and save time at reception, please complete your secure new-patient form before your visit — it takes about 5 minutes on your phone, and your information stays private and encrypted 🔐

      Complete it here:
      #{link}

      The link is valid for 14 days. Reply here any time if you have questions.
    MSG
  end
end
