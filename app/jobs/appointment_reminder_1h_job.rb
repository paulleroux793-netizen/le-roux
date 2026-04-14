class AppointmentReminder1hJob < ApplicationJob
  queue_as :default

  # Sends 1-hour reminders for appointments starting within the next 45–75 minutes.
  #
  # The asymmetric window (centred on 60 min, ±15 min) means no appointment slot
  # ever falls in two consecutive hourly windows — even with clock drift or retry —
  # so patients never receive duplicate 1h reminders.
  def perform
    window_start = 45.minutes.from_now
    window_end   = 75.minutes.from_now

    appointments = Appointment
      .where(status: [:scheduled, :confirmed])
      .where(start_time: window_start..window_end)
      .includes(:patient)
      .order(:start_time)

    Rails.logger.info("[Reminder1h] Sending reminders for #{appointments.count} appointment(s) in the 45–75 min window")

    template_service = WhatsappTemplateService.new

    appointments.each do |appointment|
      begin
        template_service.send_reminder_1h(appointment.patient, appointment)
        Rails.logger.info("[Reminder1h] Sent to #{appointment.patient.phone} (appointment #{appointment.id})")
      rescue WhatsappTemplateService::Error => e
        Rails.logger.error("[Reminder1h] Failed for appointment #{appointment.id}: #{e.message}")
      end
    end
  end
end
