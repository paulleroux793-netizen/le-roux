class PagesController < ApplicationController
  def dashboard
    today = Date.current

    page_data = dev_page_cache("dashboard", today.iso8601) do
      todays_appointments = Appointment
        .includes(:patient)
        .where(start_time: today.all_day)
        .order(:start_time)
        .to_a

      upcoming_appointments = Appointment
        .includes(:patient)
        .where("start_time > ?", Time.current)
        .where.not(status: :cancelled)
        .order(:start_time)
        .limit(6)
        .to_a

      # Reminders widget — appointments today that are still `scheduled`
      # (unconfirmed). This is what the reception actually needs to chase up.
      reminders = todays_appointments.select { |appointment| appointment.status == "scheduled" }

      # Weekly appointment breakdown by status for the chart.
      # Shows Mon–Sun of the current week so reception can see the
      # distribution at a glance.
      week_start = today.beginning_of_week(:monday)
      week_end   = today.end_of_week(:monday)
      week_appointments = Appointment
        .where(start_time: week_start.beginning_of_day..week_end.end_of_day)
        .to_a

      weekly_chart = (0..6).map do |offset|
        day = week_start + offset.days
        day_apts = week_appointments.select { |a| a.start_time.to_date == day }
        {
          day: day.strftime("%a"),
          date: day.iso8601,
          scheduled: day_apts.count { |a| a.status == "scheduled" },
          confirmed: day_apts.count { |a| a.status == "confirmed" },
          completed: day_apts.count { |a| a.status == "completed" },
          cancelled: day_apts.count { |a| a.status == "cancelled" },
          total: day_apts.size
        }
      end

      # Recent patients for the patients table
      recent_patients = Patient
        .left_joins(:appointments)
        .select(
          "patients.*",
          "COUNT(appointments.id) AS appointment_count",
          "MAX(appointments.start_time) AS last_appointment_at"
        )
        .group("patients.id")
        .order("patients.created_at DESC")
        .limit(8)
        .to_a

      # Lightweight patient list for the appointment create modal on the dashboard.
      all_patients = Patient.order(:first_name, :last_name).limit(500).select(:id, :first_name, :last_name, :phone).to_a

      {
        stats: {
          todays_appointments: todays_appointments.size,
          pending_confirmations: reminders.size,
          confirmed_today: todays_appointments.count { |appointment| appointment.status == "confirmed" },
          total_patients: Patient.count,
          new_patients_month: Patient.where("created_at >= ?", today.beginning_of_month).count,
          total_appointments: Appointment.where.not(status: :cancelled).count,
          whatsapp_messages: Conversation.by_channel("whatsapp").where("updated_at >= ?", 7.days.ago).count,
          flagged_patients: ConfirmationLog.flagged.joins(:appointment).where(appointments: { start_time: today.all_day }).count,
          completed_today: todays_appointments.count { |a| a.status == "completed" }
        },
        todays_appointments: todays_appointments.map { |a| appointment_props(a) },
        upcoming_appointments: upcoming_appointments.map { |a| appointment_props(a) },
        weekly_chart: weekly_chart,
        recent_patients: recent_patients.map { |p| patient_dashboard_props(p) },
        reminders: reminders.map { |a| appointment_props(a) },
        patients: all_patients.map { |p| { id: p.id, name: p.full_name, phone: p.phone } }
      }
    end

    render inertia: "Dashboard", props: page_data
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

  def patient_dashboard_props(patient)
    {
      id: patient.id,
      name: patient.full_name,
      phone: patient.phone,
      email: patient.email,
      appointment_count: patient.respond_to?(:appointment_count) ? patient.appointment_count : 0,
      last_appointment_at: patient.respond_to?(:last_appointment_at) && patient.last_appointment_at ? patient.last_appointment_at.iso8601 : nil,
      created_at: patient.created_at.iso8601
    }
  end
end
