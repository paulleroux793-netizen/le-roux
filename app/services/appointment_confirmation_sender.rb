class AppointmentConfirmationSender
  def initialize(appointment)
    @appointment = appointment
    @patient     = appointment.patient
  end

  # Sends the interactive confirmation request and logs the attempt.
  def send
    WhatsappTemplateService.new.send_confirmation_request_with_buttons(@patient, @appointment)

    @appointment.confirmation_logs.create!(
      method:   "whatsapp",
      outcome:  nil,
      attempts: @appointment.confirmation_logs.count + 1,
      flagged:  false,
      notes:    "Interactive confirmation request sent"
    )

    Rails.logger.info(
      "[ConfirmationSender] Sent confirmation request for appointment " \
      "#{@appointment.id} → #{@patient.phone}"
    )
  rescue WhatsappTemplateService::Error => e
    Rails.logger.error(
      "[ConfirmationSender] Failed for appointment #{@appointment.id}: #{e.message}"
    )
    raise
  end
end
