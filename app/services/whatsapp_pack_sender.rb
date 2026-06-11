# Post-booking WhatsApp for a WEBSITE booking. A website visitor has NOT messaged our
# WhatsApp number, so there is NO open 24-hour service window — free-form sends (the old
# 4-message pack) are rejected by Twilio (error 63016). The ONLY compliant first contact is a
# pre-approved Content template, so we send the approved appointment-CONFIRMATION template
# (already used by the bot/reminders). The location, directions and the secure intake-form link
# are shown to the visitor IN THE WIDGET (see WebChatService#confirmation_reply), where delivery
# is guaranteed and needs no open window.
# Best-effort: a send failure NEVER raises into the booking path — the patient is already booked.
class WhatsappPackSender
  def self.call(appointment) = new.call(appointment)

  def call(appointment)
    patient = appointment.patient
    return { sent: 0, failed: 0, skipped: true } if patient&.phone.blank?

    # SAFETY: dry-run by default. No real WhatsApp is sent from the web channel until Paul
    # explicitly sets WEB_CHAT_SEND_WHATSAPP=true on go-live. In preview/staging this just logs.
    unless ActiveModel::Type::Boolean.new.cast(ENV["WEB_CHAT_SEND_WHATSAPP"])
      Rails.logger.info("[WhatsappPack] DRY-RUN (WEB_CHAT_SEND_WHATSAPP off) — would send confirmation template to #{patient.phone}")
      return { sent: 0, failed: 0, dry_run: true }
    end

    WhatsappTemplateService.new.send_confirmation(patient, appointment)
    { sent: 1, failed: 0, skipped: false }
  rescue StandardError => e
    Rails.logger.warn("[WhatsappPack] appt #{appointment.id} confirmation template failed: #{e.class}: #{e.message}")
    { sent: 0, failed: 1, skipped: false }
  end
end
