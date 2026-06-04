# AI email assistant — drafts (NEVER sends) a reply + a booking proposal for an
# inbound patient email, reusing the WhatsApp receptionist's brain (AiService +
# PromptBuilder + the practice knowledge base). DRAFT MODE ONLY.
#
# Two switches, BOTH OFF by default — nothing emails a patient until Paul flips them:
#   MAIL_AI_DRAFTING = true  → generate drafts (this service runs)
#   MAIL_AI_AUTOSEND = true  → actually send replies (a later, separate step)
# Reception reviews the draft in the Mailbox and sends manually until then.
class MailAiAssistant
  BOOKING_RX = /appoint|book|reschedul|cancel/i

  def self.drafting_enabled? = ENV["MAIL_AI_DRAFTING"] == "true"
  def self.autosend_enabled? = ENV["MAIL_AI_AUTOSEND"] == "true"

  def draft_for(message)
    return if message.nil? || message.sent_by_us?
    body = [ message.subject.presence, (message.body_text.presence || message.snippet) ]
           .compact.join("\n\n").to_s.strip[0, 4000]
    return if body.empty?

    ai = AiService.new
    classification = (ai.classify_intent(body, channel: :whatsapp) rescue { intent: "other", entities: {} })
    intent   = classification[:intent].to_s
    entities = classification[:entities] || {}

    message.mail_thread&.update(clinical_intent: booking?(intent) ? "appointment_request" : intent.presence)

    return unless patient_facing?(intent) # skip supplier/admin/spam

    patient = match_patient(message)
    reply   = ai.generate_response(message: body, patient: patient, channel: :whatsapp)

    draft = MailAppointmentDraft.find_or_initialize_by(mail_message_id: message.id)
    draft.patient = patient
    draft.requested_reason = entities[:treatment].presence || message.subject.to_s[0, 80]
    draft.requested_start_time = parse_when(entities)
    draft.requested_duration_minutes ||= 30
    draft.confidence = booking?(intent) ? 0.7 : 0.4
    draft.status = "pending"
    draft.extraction_metadata = (draft.extraction_metadata || {}).merge(
      "intent" => intent,
      "entities" => entities.transform_keys(&:to_s),
      "draft_reply" => reply
    )
    draft.save!
    draft
  rescue => e
    Rails.logger.warn("[MailAiAssistant] msg=#{message&.id} #{e.class}: #{e.message}")
    nil
  end

  private

  def booking?(intent) = BOOKING_RX.match?(intent.to_s)

  def patient_facing?(intent)
    booking?(intent) || %w[faq emergency pricing general greeting question].include?(intent.to_s)
  end

  def match_patient(message)
    addr = message.from_address.to_s.downcase.strip
    addr.empty? ? nil : Patient.where("LOWER(email) = ?", addr).first
  end

  def parse_when(entities)
    d = entities[:date].presence
    return nil if d.nil?
    Time.zone.parse([ d, entities[:time].presence ].compact.join(" "))
  rescue ArgumentError, TypeError
    nil
  end
end
