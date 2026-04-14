class PagesController < ApplicationController
  def dashboard
    today = Date.current

    todays_scope = Appointment
      .includes(:patient)
      .where(start_time: today.all_day)
      .order(:start_time)

    # Reminders widget — appointments today that are still `scheduled`
    # (unconfirmed). This is what the reception actually needs to chase up.
    reminders_scope = todays_scope.where(status: :scheduled)

    render inertia: "Dashboard", props: {
      stats: {
        todays_appointments: todays_scope.count,
        pending_confirmations: reminders_scope.count,
        confirmed_today: todays_scope.where(status: :confirmed).count,
        whatsapp_messages: Conversation.by_channel("whatsapp").where("updated_at >= ?", 7.days.ago).count,
        flagged_patients: ConfirmationLog.flagged.joins(:appointment).where(appointments: { start_time: today.all_day }).count
      },
      todays_appointments: todays_scope.map { |a| appointment_props(a) },
      reminders: reminders_scope.map { |a| appointment_props(a) },
      system_status: {
        database: true,
        google_calendar: ENV["GOOGLE_CALENDAR_ID"].present?,
        twilio: ENV["TWILIO_ACCOUNT_SID"].present?,
        claude_ai: ENV["ANTHROPIC_API_KEY"].present?
      }
    }
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
