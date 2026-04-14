class PagesController < ApplicationController
  def dashboard
    today = Date.current

    page_data = dev_page_cache("dashboard", today.iso8601) do
      todays_appointments = Appointment
        .includes(:patient)
        .where(start_time: today.all_day)
        .order(:start_time)
        .to_a

      # Reminders widget — appointments today that are still `scheduled`
      # (unconfirmed). This is what the reception actually needs to chase up.
      reminders = todays_appointments.select { |appointment| appointment.status == "scheduled" }

      {
        stats: {
          todays_appointments: todays_appointments.size,
          pending_confirmations: reminders.size,
          confirmed_today: todays_appointments.count { |appointment| appointment.status == "confirmed" },
          whatsapp_messages: Conversation.by_channel("whatsapp").where("updated_at >= ?", 7.days.ago).count,
          flagged_patients: ConfirmationLog.flagged.joins(:appointment).where(appointments: { start_time: today.all_day }).count
        },
        todays_appointments: todays_appointments.map { |a| appointment_props(a) },
        reminders: reminders.map { |a| appointment_props(a) }
      }
    end

    render inertia: "Dashboard", props: page_data.merge(
      system_status: {
        database: true,
        google_calendar: ENV["GOOGLE_CALENDAR_ID"].present?,
        twilio: ENV["TWILIO_ACCOUNT_SID"].present?,
        claude_ai: ENV["ANTHROPIC_API_KEY"].present?
      }
    )
  end

  private

  def appointment_props(appointment)
    {
      id: appointment.id,
      patient_name: appointment.patient.full_name,
      patient_phone: appointment.patient.phone,
      start_time: appointment.start_time.iso8601,
      end_time: appointment.end_time.iso8601,
      status: appointment.status,
      reason: appointment.reason
    }
  end
end
