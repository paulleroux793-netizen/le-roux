class AppointmentsController < ApplicationController
  CALENDAR_VIEWS = %w[timeGridWeek timeGridDay dayGridMonth].freeze
  DEFAULT_CALENDAR_VIEW = "timeGridWeek"

  # Maximum rows the client-side DataTable will paginate through.
  # For a single dental practice this is effectively "all appointments
  # you'd want to scroll" without needing server-side pagination.
  LIST_ROW_LIMIT = 500

  def index
    range_start, range_end = calendar_range
    calendar_view = requested_calendar_view
    calendar_date = calendar_anchor_date(range_start)

    page_data = dev_page_cache(
      "appointments",
      "index",
      range_start.to_date.iso8601,
      range_end.to_date.iso8601,
      calendar_view,
      calendar_date.iso8601
    ) do
      appointments = Appointment.includes(:patient).order(start_time: :desc).limit(LIST_ROW_LIMIT).to_a
      calendar_appointments = Appointment
        .includes(:patient)
        .where(start_time: range_start..range_end)
        .order(:start_time)
        .to_a

      patients = Patient.order(:first_name, :last_name).limit(500).select(:id, :first_name, :last_name, :phone).to_a
      status_counts = Appointment.group(:status).count
      total_count = status_counts.values.sum

      {
        appointments: appointments.map { |a| appointment_props(a) },
        calendar_appointments: calendar_appointments.map { |a| appointment_props(a) },
        # Lightweight patient list for the Create modal picker. Phase 9.6
        # sub-area #5 will replace this with a proper SearchController,
        # but for now 500 patients loaded inline is fine for a single-
        # clinic practice and keeps the modal self-contained.
        patients: patients.map { |p|
          { id: p.id, name: p.full_name, phone: p.phone }
        },
        calendar_meta: {
          initial_date: calendar_date.iso8601,
          range_start: range_start.iso8601,
          range_end: range_end.iso8601,
          view: calendar_view
        },
        stats: {
          total: total_count,
          scheduled: status_counts.fetch("scheduled", 0),
          confirmed: status_counts.fetch("confirmed", 0),
          cancelled: status_counts.fetch("cancelled", 0),
          completed: status_counts.fetch("completed", 0)
        }
      }
    end

    render inertia: "Appointments", props: page_data
  end

  def show
    page_data = dev_page_cache("appointments", "show", params[:id]) do
      appointment = Appointment.includes(:patient, :cancellation_reason, :confirmation_logs).find(params[:id])

      {
        appointment: detailed_appointment_props(appointment)
      }
    end

    render inertia: "AppointmentShow", props: page_data
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
    start_at = parse_time(create_params[:start_time])
    end_at   = parse_time(create_params[:end_time])

    if start_at.nil? || end_at.nil?
      return redirect_back fallback_location: appointments_location,
        alert: "Invalid start or end time",
        inertia: { errors: { start_time: "Invalid start or end time" } },
        status: :see_other
    end

    patient = Patient.find(create_params[:patient_id])

    appointment =
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

    if appointment.is_a?(Appointment)
      # Create a pending confirmation log so the reminders page
      # shows this appointment from the moment it's booked.
      appointment.confirmation_logs.create!(
        method: "whatsapp",
        outcome: nil,
        attempts: 0,
        flagged: false
      )
      NotificationService.appointment_created(appointment)
      AppointmentMailer.confirmation(appointment).deliver_later
      SmsService.send_confirmation(appointment) rescue nil
    end
    expire_appointment_caches!

    redirect_to appointments_location(appointment.start_time.to_date.iso8601),
      notice: "Appointment booked", status: :see_other
  rescue ActiveRecord::RecordNotFound
    redirect_back fallback_location: appointments_location,
      alert: "Selected patient could not be found",
      inertia: { errors: { patient_id: "Selected patient could not be found" } },
      status: :see_other
  rescue ActiveRecord::RecordInvalid => e
    redirect_back fallback_location: appointments_location(anchor_date_for(start_at)),
      alert: e.record.errors.full_messages.to_sentence,
      inertia: { errors: inertia_errors_for(e.record) },
      status: :see_other
  rescue GoogleCalendarService::Error => e
    redirect_back fallback_location: appointments_location(anchor_date_for(start_at)),
      alert: e.message,
      inertia: { errors: { base: e.message } },
      status: :see_other
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
    new_start = nil
    new_end = nil

    attrs = {}
    if update_params[:start_time].present? || update_params[:end_time].present?
      new_start = parse_time(update_params[:start_time])
      new_end   = parse_time(update_params[:end_time])

      if new_start.nil? || new_end.nil?
        return redirect_back fallback_location: appointments_location(anchor_date_for(appointment.start_time)),
          alert: "Invalid start or end time",
          inertia: { errors: { start_time: "Invalid start or end time" } },
          status: :see_other
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

    NotificationService.appointment_rescheduled(appointment) if attrs[:start_time].present?
    expire_appointment_caches!

    redirect_to appointments_location(appointment.start_time.to_date.iso8601),
      notice: "Appointment updated", status: :see_other
  rescue ActiveRecord::RecordInvalid => e
    redirect_back fallback_location: appointments_location(anchor_date_for(new_start || appointment.start_time)),
      alert: e.record.errors.full_messages.to_sentence,
      inertia: { errors: inertia_errors_for(e.record) },
      status: :see_other
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

    NotificationService.appointment_cancelled(appointment, reason: cancel_params[:category])
    AppointmentMailer.cancellation(appointment).deliver_later
    SmsService.send_cancellation(appointment) rescue nil
    expire_appointment_caches!

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
    NotificationService.appointment_confirmed(appointment)
    expire_appointment_caches!
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
    string = value.to_s

    if string.match?(/[zZ]\z|[+-]\d{2}:\d{2}\z/)
      Time.iso8601(string).in_time_zone(Time.zone)
    else
      Time.zone.parse(string)
    end
  rescue ArgumentError, TypeError
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
      patient_id: appointment.patient_id,
      patient_name: appointment.patient.full_name,
      patient_phone: appointment.patient.phone,
      start_time: appointment.start_time.iso8601,
      end_time: appointment.end_time.iso8601,
      status: appointment.status,
      reason: appointment.reason,
      notes: appointment.notes
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

  def expire_appointment_caches!
    expire_dev_page_cache("appointments/index")
    expire_dev_page_cache("appointments/show")
    expire_dev_page_cache("dashboard")
    expire_dev_page_cache("reminders/index")
    Rails.cache.delete("patients/index/stats")
  end

  def requested_calendar_view
    view = params[:calendar_view].to_s
    CALENDAR_VIEWS.include?(view) ? view : DEFAULT_CALENDAR_VIEW
  end

  def calendar_anchor_date(default_time = nil)
    if params[:calendar_date].present?
      Date.iso8601(params[:calendar_date])
    elsif default_time.present?
      default_time.to_date
    else
      Date.current
    end
  rescue ArgumentError
    default_time.present? ? default_time.to_date : Date.current
  end

  def calendar_range
    requested_start = parse_time(params[:calendar_start])
    requested_end = parse_time(params[:calendar_end])

    if requested_start.present? && requested_end.present? && requested_end > requested_start
      return [ requested_start, requested_end ]
    end

    anchor = calendar_anchor_date

    case requested_calendar_view
    when "timeGridDay"
      [
        anchor.in_time_zone.beginning_of_day,
        anchor.next_day.in_time_zone.beginning_of_day
      ]
    when "dayGridMonth"
      [
        anchor.beginning_of_month.beginning_of_week.in_time_zone.beginning_of_day,
        anchor.end_of_month.end_of_week.next_day.in_time_zone.beginning_of_day
      ]
    else
      [
        anchor.beginning_of_week.in_time_zone.beginning_of_day,
        anchor.end_of_week.next_day.in_time_zone.beginning_of_day
      ]
    end
  end

  def appointments_location(calendar_date = nil)
    return appointments_path if calendar_date.blank?

    appointments_path(calendar_date: calendar_date)
  end

  def anchor_date_for(time)
    time&.to_date&.iso8601
  end

  def inertia_errors_for(record)
    record.errors.to_hash(true).transform_values { |messages| Array(messages).first }
  end
end
