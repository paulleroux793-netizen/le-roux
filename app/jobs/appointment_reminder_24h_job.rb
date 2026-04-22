class AppointmentReminder24hJob < ApplicationJob
  queue_as :default

  def perform
    tomorrow     = Date.tomorrow
    appointments = Appointment
      .where(status: [ :scheduled, :confirmed ])
      .where(start_time: tomorrow.all_day)
      .includes(:patient)
      .order(:start_time)

    Rails.logger.info("[Reminder24h] Sending reminders for #{appointments.count} appointment(s) on #{tomorrow}")

    template_service = begin
      WhatsappTemplateService.new
    rescue StandardError
      nil
    end

    appointments.each do |appointment|
      # Send WhatsApp reminder with confirmation request
      begin
        if template_service
          # Use the approved template so outbound messages work outside Twilio's
          # 24-hour session window (free-form send_text fails with error 63016).
          template_service.send_confirmation_request_with_buttons(appointment.patient, appointment)
          appointment.confirmation_logs.create!(
            method:   "whatsapp",
            outcome:  nil,
            attempts: (appointment.confirmation_logs.count + 1),
            flagged:  false,
            notes:    "24h reminder sent"
          )
          Rails.logger.info("[Reminder24h] WhatsApp sent to #{appointment.patient.phone} (appointment #{appointment.id})")
        end
      rescue StandardError => e
        Rails.logger.error("[Reminder24h] WhatsApp failed for appointment #{appointment.id}: #{e.message}")
      end

      # Send email reminder
      begin
        AppointmentMailer.reminder(appointment).deliver_later
        Rails.logger.info("[Reminder24h] Email queued for appointment #{appointment.id}")
      rescue StandardError => e
        Rails.logger.error("[Reminder24h] Email failed for appointment #{appointment.id}: #{e.message}")
      end

      # Send SMS reminder
      begin
        SmsService.send_reminder(appointment)
        Rails.logger.info("[Reminder24h] SMS sent for appointment #{appointment.id}")
      rescue StandardError => e
        Rails.logger.error("[Reminder24h] SMS failed for appointment #{appointment.id}: #{e.message}")
      end
    end
  end
end
