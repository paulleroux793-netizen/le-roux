class AppointmentReminder24hJob < ApplicationJob
  queue_as :default

  def perform
    tomorrow     = Date.tomorrow
    appointments = Appointment
      .where(status: [:scheduled, :confirmed])
      .where(start_time: tomorrow.all_day)
      .includes(:patient)
      .order(:start_time)

    Rails.logger.info("[Reminder24h] Sending reminders for #{appointments.count} appointment(s) on #{tomorrow}")

    template_service = WhatsappTemplateService.new

    appointments.each do |appointment|
      begin
        template_service.send_reminder_24h(appointment.patient, appointment)
        Rails.logger.info("[Reminder24h] Sent to #{appointment.patient.phone} (appointment #{appointment.id})")
      rescue WhatsappTemplateService::Error => e
        Rails.logger.error("[Reminder24h] Failed for appointment #{appointment.id}: #{e.message}")
      end
    end
  end
end
