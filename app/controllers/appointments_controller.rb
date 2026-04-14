class AppointmentsController < ApplicationController
  # Number of days of appointments to pre-load for the interactive calendar
  # view. Covers ~2 weeks so FullCalendar navigation feels instant without
  # triggering a refetch.
  CALENDAR_WINDOW_DAYS = 14

  # Maximum rows the client-side DataTable will paginate through.
  # For a single dental practice this is effectively "all appointments
  # you'd want to scroll" without needing server-side pagination.
  LIST_ROW_LIMIT = 500

  def index
    appointments = Appointment.includes(:patient).order(start_time: :desc).limit(LIST_ROW_LIMIT)

    today = Date.current
    calendar_appointments = Appointment
      .includes(:patient)
      .where(start_time: (today - 3.days).beginning_of_day..(today + CALENDAR_WINDOW_DAYS.days).end_of_day)
      .order(:start_time)

    stats_scope = Appointment.all

    render inertia: "Appointments", props: {
      appointments: appointments.map { |a| appointment_props(a) },
      calendar_appointments: calendar_appointments.map { |a| appointment_props(a) },
      # Lightweight patient list for the Create modal picker. Phase 9.6
      # sub-area #5 will replace this with a proper SearchController,
      # but for now 500 patients loaded inline is fine for a single-
      # clinic practice and keeps the modal self-contained.
      patients: Patient.order(:first_name, :last_name).limit(500).map { |p|
        { id: p.id, name: p.full_name, phone: p.phone }
      },
      stats: {
        total: stats_scope.count,
        scheduled: stats_scope.where(status: :scheduled).count,
        confirmed: stats_scope.where(status: :confirmed).count,
        cancelled: stats_scope.where(status: :cancelled).count,
        completed: stats_scope.where(status: :completed).count
      }
    }
  end

  def show
    appointment = Appointment.includes(:patient, :cancellation_reason, :confirmation_logs).find(params[:id])

    render inertia: "AppointmentShow", props: {
      appointment: detailed_appointment_props(appointment)
    }
  end

  # POST /appointments
  #
  # Creates a new appointment for an existing patient. If Google Calendar
  # is configured (GOOGLE_CALENDAR_ID env present) we go through
  # GoogleCalendarService#book_appointment so the DB row and the Google
  # event are created atomically. Otherwise we fall back to a local-only
  # Appointment row — useful for dev and for practices that aren't using
  # the Google integration yet.
  def create
    patient = Patient.find(create_params[:patient_id])
    start_at = parse_time(create_params[:start_time])
    end_at   = parse_time(create_params[:end_time])

    if start_at.nil? || end_at.nil?
      return redirect_back fallback_location: appointments_path,
        alert: "Invalid start or end time", status: :see_other
    end

    if ENV["GOOGLE_CALENDAR_ID"].present?
      GoogleCalendarService.new.book_appointment(
        patient: patient,
        start_time: start_at,
        end_time: end_at,
        reason: create_params[:reason]
      )
    else
      patient.appointments.create!(
        start_time: start_at,
        end_time: end_at,
        reason: create_params[:reason],
        notes: create_params[:notes],
        status: :scheduled
      )
    end

    redirect_back fallback_location: appointments_path,
      notice: "Appointment booked", status: :see_other
  rescue ActiveRecord::RecordInvalid => e
    redirect_back fallback_location: appointments_path,
      alert: e.record.errors.full_messages.to_sentence, status: :see_other
  rescue GoogleCalendarService::Error => e
    redirect_back fallback_location: appointments_path,
      alert: e.message, status: :see_other
  end

  # PATCH /appointments/:id
  #
  # Used by:
  #   - Calendar drag-and-drop reschedule (start_time / end_time only)
  #   - Edit modal (any of start_time, end_time, reason, notes)
  #
  # When a Google Calendar event is linked we keep it in sync via the
  # existing GoogleCalendarService — on sync failure we still persist
  # the local change and log the error so the dashboard reflects it.
  def update
    appointment = Appointment.find(params[:id])

    attrs = {}
    if update_params[:start_time].present? || update_params[:end_time].present?
      new_start = parse_time(update_params[:start_time])
      new_end   = parse_time(update_params[:end_time])

      if new_start.nil? || new_end.nil?
        return redirect_back fallback_location: appointments_path,
          alert: "Invalid start or end time", status: :see_other
      end
      attrs[:start_time] = new_start
      attrs[:end_time]   = new_end
    end
    attrs[:reason] = update_params[:reason] if update_params.key?(:reason)
    attrs[:notes]  = update_params[:notes]  if update_params.key?(:notes)

    Appointment.transaction do
      appointment.update!(attrs)
    end

    sync_google_calendar(appointment) if attrs[:start_time].present?

    redirect_back fallback_location: appointments_path,
      notice: "Appointment updated", status: :see_other
  rescue ActiveRecord::RecordInvalid => e
    redirect_back fallback_location: appointments_path,
      alert: e.record.errors.full_messages.to_sentence, status: :see_other
  end

  # PATCH /appointments/:id/cancel
  #
  # Cancels an appointment and (optionally) stores a structured
  # CancellationReason. Works for both Google-linked and local-only
  # appointments.
  def cancel
    appointment = Appointment.find(params[:id])

    Appointment.transaction do
      appointment.cancelled!
      if cancel_params[:category].present?
        appointment.cancellation_reason&.destroy
        appointment.create_cancellation_reason!(
          reason_category: cancel_params[:category],
          details: cancel_params[:details]
        )
      end
    end

    if appointment.google_event_id.present?
      begin
        GoogleCalendarService.new.cancel_appointment(
          appointment.google_event_id,
          reason_category: cancel_params[:category],
          reason_details: cancel_params[:details]
        )
      rescue StandardError => e
        Rails.logger.error("[AppointmentsController#cancel] Google sync failed: #{e.message}")
      end
    end

    redirect_back fallback_location: appointments_path,
      notice: "Appointment cancelled", status: :see_other
  rescue ActiveRecord::RecordInvalid => e
    redirect_back fallback_location: appointments_path,
      alert: e.record.errors.full_messages.to_sentence, status: :see_other
  end

  # PATCH /appointments/:id/confirm
  #
  # One-click confirm — flips status to :confirmed. Intentionally
  # separate from #update so the UI can wire a single button without
  # constructing a full params hash.
  def confirm
    appointment = Appointment.find(params[:id])
    appointment.confirmed!
    redirect_back fallback_location: appointments_path,
      notice: "Appointment confirmed", status: :see_other
  end

  private

  def create_params
    params.require(:appointment).permit(:patient_id, :start_time, :end_time, :reason, :notes)
  end

  def update_params
    params.require(:appointment).permit(:start_time, :end_time, :reason, :notes)
  end

  def cancel_params
    params.fetch(:cancellation, {}).permit(:category, :details)
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
