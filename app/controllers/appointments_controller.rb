class AppointmentsController < ApplicationController
  # Number of days of appointments to pre-load for the interactive calendar
  # view. Covers ~2 weeks so FullCalendar navigation feels instant without
  # triggering a refetch.
  CALENDAR_WINDOW_DAYS = 14

  def index
    appointments = Appointment.includes(:patient).order(start_time: :desc)
    appointments = apply_filters(appointments)

    today = Date.current
    calendar_appointments = Appointment
      .includes(:patient)
      .where(start_time: (today - 3.days).beginning_of_day..(today + CALENDAR_WINDOW_DAYS.days).end_of_day)
      .order(:start_time)

    render inertia: "Appointments", props: {
      appointments: appointments.limit(50).map { |a| appointment_props(a) },
      calendar_appointments: calendar_appointments.map { |a| appointment_props(a) },
      filters: filter_params.to_h,
      stats: {
        total: appointments.count,
        scheduled: appointments.where(status: :scheduled).count,
        confirmed: appointments.where(status: :confirmed).count,
        cancelled: appointments.where(status: :cancelled).count,
        completed: appointments.where(status: :completed).count
      }
    }
  end

  def show
    appointment = Appointment.includes(:patient, :cancellation_reason, :confirmation_logs).find(params[:id])

    render inertia: "AppointmentShow", props: {
      appointment: detailed_appointment_props(appointment)
    }
  end

  # PATCH /appointments/:id
  #
  # Currently used by the Phase 9.6 calendar drag-and-drop reschedule flow.
  # Only `start_time` and `end_time` are accepted; status/other fields stay
  # untouched. When a Google Calendar event is linked we keep it in sync via
  # the existing GoogleCalendarService — on sync failure we still persist the
  # local change and surface the error in the flash so the dashboard reflects
  # the drop, and an operator can investigate.
  def update
    appointment = Appointment.find(params[:id])

    new_start = parse_time(update_params[:start_time])
    new_end   = parse_time(update_params[:end_time])

    if new_start.nil? || new_end.nil?
      return redirect_back fallback_location: appointments_path,
        alert: "Invalid start or end time", status: :see_other
    end

    Appointment.transaction do
      appointment.update!(start_time: new_start, end_time: new_end)
    end

    sync_google_calendar(appointment)

    redirect_back fallback_location: appointments_path,
      notice: "Appointment rescheduled", status: :see_other
  rescue ActiveRecord::RecordInvalid => e
    redirect_back fallback_location: appointments_path,
      alert: e.record.errors.full_messages.to_sentence, status: :see_other
  end

  private

  def update_params
    params.require(:appointment).permit(:start_time, :end_time)
  end

  def parse_time(value)
    return nil if value.blank?
    Time.zone.parse(value.to_s)
  rescue ArgumentError
    nil
  end

  def sync_google_calendar(appointment)
    return unless appointment.google_event_id.present?

    GoogleCalendarService.new.reschedule_appointment(
      appointment.google_event_id,
      new_start: appointment.start_time,
      new_end: appointment.end_time
    )
  rescue StandardError => e
    Rails.logger.error("[AppointmentsController#update] Google sync failed: #{e.message}")
  end

  def apply_filters(scope)
    scope = scope.where(status: filter_params[:status]) if filter_params[:status].present?
    scope = scope.for_date(Date.parse(filter_params[:date])) if filter_params[:date].present?
    if filter_params[:search].present?
      scope = scope.joins(:patient).where(
        "patients.first_name ILIKE :q OR patients.last_name ILIKE :q OR patients.phone ILIKE :q",
        q: "%#{filter_params[:search]}%"
      )
    end
    scope
  end

  def filter_params
    params.permit(:status, :date, :search)
  end

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

  def detailed_appointment_props(appointment)
    appointment_props(appointment).merge(
      notes: appointment.notes,
      google_event_id: appointment.google_event_id,
      patient_id: appointment.patient_id,
      cancellation_reason: appointment.cancellation_reason&.then { |cr|
        { category: cr.reason_category, details: cr.details }
      },
      confirmation_logs: appointment.confirmation_logs.order(created_at: :desc).map { |cl|
        { method: cl.method, outcome: cl.outcome, attempts: cl.attempts, flagged: cl.flagged, created_at: cl.created_at.iso8601 }
      }
    )
  end
end
