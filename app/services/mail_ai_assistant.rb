require "anthropic"

# AI email assistant — drafts (NEVER sends) a reply + a booking proposal for an
# inbound patient email. Email triage uses its OWN email-aware prompt (the
# WhatsApp classifier returns empty on email-formatted text); the REPLY reuses
# the WhatsApp receptionist brain (AiService + the practice knowledge base).
#
# DRAFT MODE ONLY. Two switches, BOTH OFF by default:
#   MAIL_AI_DRAFTING = true → generate drafts (this service runs)
#   MAIL_AI_AUTOSEND = true → actually send (a later, separate step)
class MailAiAssistant
  def self.drafting_enabled? = ENV["MAIL_AI_DRAFTING"] == "true"
  def self.autosend_enabled? = ENV["MAIL_AI_AUTOSEND"] == "true"

  def draft_for(message)
    return if message.nil? || message.sent_by_us?
    body = [ message.subject.presence, (message.body_text.presence || message.snippet) ]
           .compact.join("\n\n").to_s.strip[0, 6000]
    return if body.empty?

    triage = classify_email(body)
    message.mail_thread&.update(
      clinical_intent: triage["is_booking"] ? "appointment_request" : (triage["patient_facing"] ? "question" : "other")
    )
    return unless triage["patient_facing"] # skip supplier/admin/marketing/spam

    patient = match_patient(message)
    reply   = (AiService.new.generate_response(message: body, patient: patient, channel: :whatsapp) rescue nil)

    draft = MailAppointmentDraft.find_or_initialize_by(mail_message_id: message.id)
    draft.patient = patient
    draft.requested_reason = triage["treatment"].presence || message.subject.to_s[0, 80]
    draft.requested_start_time = parse_when(triage["date"], triage["time"])
    draft.requested_duration_minutes ||= 30
    draft.confidence = triage["is_booking"] ? 0.7 : 0.4
    draft.status = "pending"
    draft.extraction_metadata = (draft.extraction_metadata || {}).merge("triage" => triage, "draft_reply" => reply)
    draft.save!
    draft
  rescue => e
    Rails.logger.warn("[MailAiAssistant] msg=#{message&.id} #{e.class}: #{e.message}")
    nil
  end

  private

  # Email-aware triage (its own prompt — robust to email format).
  def classify_email(body)
    client = Anthropic::Client.new(access_token: ENV["ANTHROPIC_API_KEY"])
    system = <<~PROMPT
      You triage incoming EMAIL for a South African dental practice (Dr Chalita le Roux Inc).
      Decide if it is PATIENT-FACING (a booking, reschedule/cancel, dental question, or patient enquiry)
      vs supplier / admin / accounts / marketing / newsletter / spam (NOT patient-facing).
      If patient-facing and it's a booking, extract the details. Interpret relative dates
      (e.g. "next Tuesday") against TODAY = #{Date.current.iso8601} (Africa/Johannesburg).
      Return ONLY compact JSON, no prose, no code fences:
      {"patient_facing": true|false, "is_booking": true|false, "date": "YYYY-MM-DD"|null, "time": "HH:MM"|null, "treatment": <string>|null, "patient_name": <string>|null}
    PROMPT
    resp = client.messages(parameters: {
      model: ENV.fetch("ANTHROPIC_SUMMARY_MODEL", "claude-haiku-4-5-20251001"),
      max_tokens: 300, system: system,
      messages: [ { role: "user", content: body } ]
    })
    txt = (resp.dig("content", 0, "text") || resp["content"].to_s)
          .gsub(/\A```(?:json)?\s*/, "").gsub(/```\s*\z/, "").strip
    JSON.parse(txt)
  rescue => e
    Rails.logger.warn("[MailAiAssistant] classify_email #{e.class}: #{e.message}")
    { "patient_facing" => false, "is_booking" => false }
  end

  def match_patient(message)
    addr = message.from_address.to_s.downcase.strip
    addr.empty? ? nil : Patient.where("LOWER(email) = ?", addr).first
  end

  def parse_when(date, time)
    return nil if date.blank?
    Time.zone.parse([ date, time.presence ].compact.join(" "))
  rescue ArgumentError, TypeError
    nil
  end
end
