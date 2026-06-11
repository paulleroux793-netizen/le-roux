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
      appointments = Appointment.includes(:provider, patient: :billing_accounts).order(start_time: :desc).limit(LIST_ROW_LIMIT).to_a
      calendar_appointments = Appointment
        .includes(:provider, patient: :billing_accounts)
        .where(start_time: range_start..range_end)
        .order(:start_time)
        .to_a

      patients = Patient.order(:first_name, :last_name).limit(500).select(:id, :first_name, :last_name, :phone).to_a
      status_counts = Appointment.group(:status).count
      total_count = status_counts.values.sum

      {
        appointments: appointments.map { |a| appointment_props(a) },
        calendar_appointments: calendar_appointments.map { |a| appointment_props(a) },
        calendar_notes: CalendarNote.between(range_start, range_end).order(:starts_at).map { |n| calendar_note_props(n) },
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

  # GET /appointments/calendar
  #
  # Dedicated full-screen calendar page. Same calendar payload as #index
  # (week grid + patient picker for the create modal) but rendered without
  # the dashboard chrome / stat cards so the whole working day fits the
  # screen. Reception lives here for day-to-day booking.
  def calendar
    range_start, range_end = calendar_range
    calendar_view = requested_calendar_view
    calendar_date = calendar_anchor_date(range_start)

    page_data = dev_page_cache(
      "appointments",
      "calendar",
      range_start.to_date.iso8601,
      range_end.to_date.iso8601,
      calendar_view,
      calendar_date.iso8601
    ) do
      calendar_appointments = Appointment
        .includes(:provider, patient: :billing_accounts)
        .where(start_time: range_start..range_end)
        .order(:start_time)
        .to_a

      patients = Patient.order(:first_name, :last_name).limit(500).select(:id, :first_name, :last_name, :phone).to_a

      {
        calendar_appointments: calendar_appointments.map { |a| appointment_props(a) },
        calendar_notes: CalendarNote.between(range_start, range_end).order(:starts_at).map { |n| calendar_note_props(n) },
        patients: patients.map { |p| { id: p.id, name: p.full_name, phone: p.phone } },
        calendar_meta: {
          initial_date: calendar_date.iso8601,
          range_start: range_start.iso8601,
          range_end: range_end.iso8601,
          view: calendar_view
        }
      }
    end

    render inertia: "CalendarFullscreen", props: page_data
  end

  # GET /diary?date=YYYY-MM-DD
  # The Elixir-style day diary: one column per active dentist. Shows Ivory's own
  # (editable) appointments plus the read-only Elixir history for the same day.
  def diary
    date = parse_diary_date(params[:date])
    day_start = date.in_time_zone.beginning_of_day
    day_end   = date.in_time_zone.end_of_day

    providers = Provider.active.ordered.to_a
    prov_by_norm = Provider.all.index_by { |p| normalize_provider_name(p.name) }

    # Keep cancelled appointments visible in the diary (greyed, not removed) —
    # Paul's requirement: cancelling never deletes from the diary.
    appts = Appointment.includes(:provider, patient: :billing_accounts)
                       .where(start_time: day_start..day_end)
                       .order(:start_time).to_a

    snapshots = ElixirDiarySnapshot.where(diary_date: date).order(:appointment_start_at).to_a

    render inertia: "Diary", props: {
      date: date.iso8601,
      providers: providers.map { |p|
        { id: p.id, name: p.display_name, full_name: p.name, color: p.color, position: p.position,
          accepting_bookings: p.accepting_bookings,
          unavailable_until: p.unavailable_until&.iso8601,
          on_leave: p.on_leave_on?(date) }
      },
      appointments: appts.map { |a| appointment_props(a) },
      elixir_blocks: snapshots.filter_map { |s|
        prov = prov_by_norm[normalize_provider_name(s.dentist)]
        next unless prov&.active?
        elixir_snapshot_props(s, prov)
      },
      closed_blocks: CalendarNote.between(day_start, day_end).order(:starts_at).map { |n| diary_closed_props(n) },
      patients: []
    }
  end

  # GET /diary/print?date=YYYY-MM-DD[&provider_id=] — printable day schedule in the
  # Elixir "APPOINTMENT DETAILS" layout reception posts to the practice WhatsApp group.
  # Plain print-friendly HTML (no Inertia); one page per dentist; window.print() on load.
  def print_schedule
    @date       = parse_diary_date(params[:date])
    @printed_on = Time.zone.today
    @open_time  = "08:00"
    @close_time = "17:00"

    providers = Provider.active.ordered.to_a
    providers = providers.select { |p| p.id == params[:provider_id].to_i } if params[:provider_id].present?

    day = @date.in_time_zone.beginning_of_day..@date.in_time_zone.end_of_day
    @schedules = providers.map do |prov|
      appts = Appointment.includes(:patient)
                         .where(provider_id: prov.id, start_time: day)
                         .where.not(status: :cancelled)
                         .order(:start_time)
      [ prov, appts ]
    end

    render "appointments/print_schedule", layout: false
  end

  # GET /appointments/next_available?provider_id=&duration= — JSON list of the next
  # open slots for the booking modal's "Find next available" helper.
  def next_available
    provider = Provider.find_by(id: params[:provider_id])
    slots = NextAvailableSlotFinder.call(
      provider: provider,
      duration_min: (params[:duration].presence || 30),
      limit: 3
    )
    render json: { slots: slots }
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

    # NOTE: no "must be in the future" guard — reception books walk-ins for "now"
    # and back-enters earlier-today / past visits for the record. The diary is a
    # staff tool; the model still prevents per-dentist double-booking.

    # Calendar-fix path: reception clicked an empty slot, ticked
    # "New patient", typed first/last/phone — we create the Patient
    # first, in the same DB transaction as the appointment. Both
    # succeed or neither — no orphan patients on slot-overlap rejects.
    patient =
      if params[:new_patient].present? && create_params[:patient_id].blank?
        np = params.require(:new_patient).permit(:first_name, :last_name, :phone)
        if np[:first_name].blank? || np[:last_name].blank? || np[:phone].blank?
          return redirect_back fallback_location: appointments_location,
            alert: "New patient: first name, last name, and phone are required",
            inertia: { errors: { patient_id: "New patient details are required" } },
            status: :see_other
        end
        Patient.create!(
          first_name: np[:first_name],
          last_name:  np[:last_name],
          phone:      np[:phone]
        )
      else
        Patient.find(create_params[:patient_id])
      end

    # Always persist the appointment locally. (Google Calendar sync is disabled
    # dead code; routing through it silently dropped bookings when a dummy
    # GOOGLE_CALENDAR_ID was set — the "booked but nothing saved" bug.)
    appointment = patient.appointments.create!(
      start_time: start_at,
      end_time: end_at,
      reason: create_params[:reason],
      notes: create_params[:notes],
      status: :scheduled,
      provider_id: create_params[:provider_id].presence,
      # || false: Boolean.cast(nil) is nil (not false), and asap is NOT NULL — so a booking that
      # omits the asap param (calendar quick-book, API, any non-form path) would 500 with a
      # NotNullViolation. Fall back to the DB default explicitly. 2026-06-08.
      asap: ActiveModel::Type::Boolean.new.cast(create_params[:asap]) || false
    )

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
      AuditService.log(
        action: "appointment.created",
        summary: "Booked appointment for #{appointment.patient.full_name} on #{appointment.start_time.strftime('%-d %b %Y at %H:%M')}",
        resource: appointment,
        details: { patient_id: appointment.patient_id, reason: appointment.reason, start_time: appointment.start_time.iso8601 },
        performed_by: audit_performer,
        ip_address: request.remote_ip
      )
    end
    expire_appointment_caches!

    # redirect_back so a booking made on the diary stays on the diary (and shows up);
    # falls back to the calendar location when there's no referer (e.g. specs).
    redirect_back fallback_location: appointments_location(appointment.start_time.to_date.iso8601),
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
  rescue ActiveRecord::StatementInvalid => e
    # The per-provider GiST exclusion constraint (no_overlapping_appointments_per_provider)
    # rejected the booking — another appointment was created for that slot in the
    # race window after the form's availability check. Show a friendly conflict
    # message rather than a 500. Match the PG exclusion cause as well so a future
    # constraint rename can't silently turn this back into a 500.
    raise unless overlap_violation?(e)
    redirect_back fallback_location: appointments_location(anchor_date_for(start_at)),
      alert: "That time slot was just taken by another booking. Please pick a different time.",
      inertia: { errors: { start_time: "slot no longer available" } },
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
    attrs[:provider_id] = update_params[:provider_id] if update_params.key?(:provider_id)

    Appointment.transaction do
      appointment.update!(attrs)
    end

    sync_google_calendar(appointment) if attrs[:start_time].present?

    NotificationService.appointment_rescheduled(appointment) if attrs[:start_time].present?

    AuditService.log(
      action: "appointment.updated",
      summary: "Updated appointment for #{appointment.patient.full_name} on #{appointment.start_time.strftime('%-d %b %Y at %H:%M')}",
      resource: appointment,
      details: attrs.transform_values { |v| v.respond_to?(:iso8601) ? v.iso8601 : v },
      performed_by: audit_performer,
      ip_address: request.remote_ip
    )
    expire_appointment_caches!

    # redirect_back (not redirect_to) so a drag/cut-paste move on the
    # full-screen /calendar page stays there instead of bouncing to the
    # dashboard /appointments list. Inline view still lands on /appointments.
    redirect_back fallback_location: appointments_location(appointment.start_time.to_date.iso8601),
      notice: "Appointment updated", status: :see_other
  rescue ActiveRecord::RecordInvalid => e
    redirect_back fallback_location: appointments_location(anchor_date_for(new_start || appointment.start_time)),
      alert: e.record.errors.full_messages.to_sentence,
      inertia: { errors: inertia_errors_for(e.record) },
      status: :see_other
  rescue ActiveRecord::StatementInvalid => e
    # Reschedule moved the appointment onto an occupied slot — blocked by the
    # per-provider GiST exclusion constraint (the model validation also runs on
    # :update, but the DB constraint is the race-proof guard).
    raise unless overlap_violation?(e)
    redirect_back fallback_location: appointments_location(anchor_date_for(new_start || appointment.start_time)),
      alert: "That time slot is already booked. Please choose a different time.",
      inertia: { errors: { start_time: "slot already booked" } },
      status: :see_other
  end

  # True when a StatementInvalid was caused by the appointments per-provider
  # overlap exclusion constraint (race-window double-booking), so callers can
  # show a friendly "slot taken" message instead of a 500. Matches both the
  # constraint name and the underlying PG exclusion class for resilience.
  def overlap_violation?(e)
    e.message.include?("no_overlapping_appointments") ||
      (defined?(PG::ExclusionViolation) && e.cause.is_a?(PG::ExclusionViolation))
  end
  private :overlap_violation?

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
    AuditService.log(
      action: "appointment.cancelled",
      summary: "Cancelled appointment for #{appointment.patient.full_name} on #{appointment.start_time.strftime('%-d %b %Y at %H:%M')}",
      resource: appointment,
      details: { reason_category: cancel_params[:category], details: cancel_params[:details] }.compact,
      performed_by: audit_performer,
      ip_address: request.remote_ip
    )
    expire_appointment_caches!

    redirect_back fallback_location: appointments_path,
      notice: "Appointment cancelled", status: :see_other
  rescue ActiveRecord::RecordInvalid => e
    redirect_back fallback_location: appointments_path,
      alert: e.record.errors.full_messages.to_sentence, status: :see_other
  end

  # DELETE /appointments/:id
  #
  # PERMANENTLY removes the appointment from the diary — a hard delete, distinct
  # from #cancel (which greys it and keeps it). cancellation_reason and
  # confirmation_logs cascade via dependent: :destroy. Audited; irreversible.
  def destroy
    appointment  = Appointment.find(params[:id])
    patient_name = appointment.patient&.full_name
    when_str     = appointment.start_time.strftime("%-d %b %Y at %H:%M")
    details = { patient_id: appointment.patient_id, start_time: appointment.start_time.iso8601, status: appointment.status }

    appointment.destroy!

    AuditService.log(
      action: "appointment.deleted",
      summary: "Permanently deleted appointment for #{patient_name} on #{when_str}",
      details: details,
      performed_by: audit_performer,
      ip_address: request.remote_ip
    )
    expire_appointment_caches!

    redirect_back fallback_location: diary_path, notice: "Appointment deleted", status: :see_other
  rescue ActiveRecord::RecordNotFound
    redirect_back fallback_location: diary_path, alert: "Appointment not found", status: :see_other
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
    AuditService.log(
      action: "appointment.confirmed",
      summary: "Confirmed appointment for #{appointment.patient.full_name} on #{appointment.start_time.strftime('%-d %b %Y at %H:%M')}",
      resource: appointment,
      performed_by: audit_performer,
      ip_address: request.remote_ip
    )
    expire_appointment_caches!
    redirect_back fallback_location: appointments_path,
      notice: "Appointment confirmed", status: :see_other
  end

  # PATCH /appointments/:id/set_status
  #
  # Front-desk patient-journey transitions driven from the calendar pop-over:
  # confirmed → arrived → in_consultation → completed (and back to scheduled
  # if a click was a mistake). Each maps to a colour on the calendar so
  # reception can read the room at a glance.
  STATUS_TRANSITIONS = %w[scheduled confirmed arrived in_consultation completed no_show cancelled].freeze

  def set_status
    appointment = Appointment.find(params[:id])
    new_status = params[:status].to_s

    unless STATUS_TRANSITIONS.include?(new_status)
      return redirect_back fallback_location: appointments_path,
        alert: "Unknown status: #{new_status}", status: :see_other
    end

    appointment.update!(status: new_status)

    # P9.4 — Auto-start an AI scribe session when the patient sits in the
    # chair. Idempotent: if a session is already recording for this
    # appointment we don't spawn a second. Best-effort — a scribe failure
    # must never block the front-desk status change.
    scribe_started = maybe_start_scribe(appointment) if new_status == "in_consultation"

    # N3 — Generate the end-of-appointment bullet summary when reception
    # marks the visit completed. Best-effort: a summary failure must
    # never block the journey button.
    summary_generated = maybe_summarise(appointment) if new_status == "completed"

    AuditService.log(
      action: "appointment.status_changed",
      summary: "Marked #{appointment.patient.full_name}'s appointment as #{new_status.humanize} (#{appointment.start_time.strftime('%-d %b at %H:%M')})",
      resource: appointment,
      details: { status: new_status, scribe_started: !!scribe_started, summary_generated: !!summary_generated }.compact,
      performed_by: audit_performer,
      ip_address: request.remote_ip
    )
    expire_appointment_caches!
    notice = "Marked as #{new_status.humanize}"
    notice += " · Scribe recording started" if scribe_started
    redirect_back fallback_location: appointments_path,
      notice: notice, status: :see_other
  rescue ActiveRecord::RecordInvalid => e
    redirect_back fallback_location: appointments_path,
      alert: e.record.errors.full_messages.to_sentence, status: :see_other
  end

  # POST /appointments/:id/whatsapp_pack — send the 4 standard WhatsApp messages to the patient
  # (Location, Directions, Intake form, Confirmation). Reception-triggered; sends real messages.
  def whatsapp_pack
    appt = Appointment.find(params[:id])
    send_standard_whatsapp(appt, WhatsappStandardMessages.pack(appt), "4-message pack")
  end

  # POST /appointments/:id/whatsapp_confirm — send ONLY the booking confirmation (this date/time).
  def whatsapp_confirm
    appt = Appointment.find(params[:id])
    send_standard_whatsapp(appt, [ WhatsappStandardMessages.confirmation(appt) ], "booking confirmation")
  end

  private

  # Dispatch one or more standard messages to the appointment's patient via the existing free-form
  # WhatsApp sender. Each send is isolated so one failure (e.g. the patient is outside Twilio's
  # 24-hour reply window) doesn't abort the rest; reception sees how many went through.
  def send_standard_whatsapp(appt, messages, label)
    phone = appt.patient&.phone
    return redirect_back(fallback_location: appointments_location, alert: "No phone number on file for this patient.", status: :see_other) if phone.blank?

    svc = WhatsappTemplateService.new
    sent = 0
    failed = 0
    messages.each do |body|
      svc.send_text(phone, body)
      sent += 1
    rescue StandardError => e
      failed += 1
      Rails.logger.warn("[whatsapp_standard] appt #{appt.id} send failed: #{e.message}")
    end

    if defined?(AuditService)
      AuditService.log(action: "appointment.whatsapp_standard",
        summary: "Sent #{sent}/#{messages.size} standard WhatsApp message(s) (#{label}) to #{appt.patient&.full_name}",
        resource: appt, performed_by: audit_performer, ip_address: request.remote_ip)
    end

    msg = "WhatsApp #{label}: #{sent} sent"
    msg += " · #{failed} failed (patient may be outside the 24-hour reply window — needs an approved template)" if failed.positive?
    redirect_back fallback_location: appointments_location, notice: msg, status: :see_other
  end

  def create_params
    params.require(:appointment).permit(:patient_id, :start_time, :end_time, :reason, :notes, :provider_id, :asap)
  end

  def update_params
    params.require(:appointment).permit(:start_time, :end_time, :reason, :notes, :provider_id, :asap)
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
    patient = appointment.patient
    {
      id: appointment.id,
      patient_id: appointment.patient_id,
      patient_name: patient.full_name,
      patient_phone: patient.phone,
      patient_email: patient.email,
      patient_dob: patient.date_of_birth&.iso8601,
      patient_language: patient.preferred_language,
      # "New" = this is the patient's only/earliest appointment. Lets the
      # pop-over show new-vs-existing without a server round-trip on click.
      is_new_patient: patient.appointments.where.not(id: appointment.id).none?,
      account_code: patient.account_code,
      provider_id: appointment.provider_id,
      provider_name: appointment.provider&.display_name,
      provider_color: appointment.provider&.color,
      status_color: appointment.status_color,
      start_time: appointment.start_time.iso8601,
      end_time: appointment.end_time.iso8601,
      status: appointment.status,
      reason: appointment.reason,
      notes: appointment.notes
    }
  end

  def parse_diary_date(value)
    value.present? ? Date.iso8601(value) : Time.zone.today
  rescue ArgumentError
    Time.zone.today
  end

  # Comma-separated `dates` (Ctrl/Shift multi-select + Next-7/Month buttons),
  # falling back to single `date`, falling back to today. Capped at 31 days.
  def parse_diary_dates(dates_param, date_param)
    if dates_param.present?
      list = dates_param.to_s.split(",").filter_map { |s|
        begin
          Date.iso8601(s.strip)
        rescue ArgumentError
          nil
        end
      }.uniq.sort
      return list.first(31) if list.any?
    end
    [ parse_diary_date(date_param) ]
  end

  def parse_int_list(value)
    value.to_s.split(",").map(&:to_i).select(&:positive?)
  end

  # One day's worth of diary data (appointments + read-only Elixir history + closed blocks).
  def diary_day_payload(date, prov_by_norm)
    day_start = date.in_time_zone.beginning_of_day
    day_end   = date.in_time_zone.end_of_day

    # Keep cancelled appointments visible in the diary (greyed, not removed) —
    # Paul's requirement: cancelling never deletes from the diary.
    appts = Appointment.includes(:provider, patient: :billing_accounts)
                       .where(start_time: day_start..day_end)
                       .order(:start_time).to_a

    snapshots = ElixirDiarySnapshot.where(diary_date: date).order(:appointment_start_at).to_a

    {
      date: date.iso8601,
      appointments: appts.map { |a| appointment_props(a) },
      elixir_blocks: snapshots.filter_map { |s|
        prov = prov_by_norm[normalize_provider_name(s.dentist)]
        next unless prov&.active?
        elixir_snapshot_props(s, prov)
      },
      closed_blocks: CalendarNote.between(day_start, day_end).order(:starts_at).map { |n| diary_closed_props(n) }
    }
  end

  def normalize_provider_name(value)
    value.to_s.downcase.gsub(/[^a-z]/, "")
  end

  # Read-only block sourced from the Elixir diary mirror (not editable in Ivory).
  # Rendered neutral/faded — it's historical context, its live status isn't tracked.
  def elixir_snapshot_props(snapshot, provider)
    {
      id: "elixir-#{snapshot.id}",
      source: "elixir",
      provider_id: provider.id,
      patient_name: snapshot.patient_name,
      account_code: snapshot.account_code.presence,
      reason: snapshot.reason,
      is_new_patient: snapshot.is_new_patient,
      start_time: snapshot.appointment_start_at.iso8601,
      end_time: snapshot.appointment_end_at.iso8601
    }
  end

  def diary_closed_props(note)
    {
      id: note.id,
      provider_id: note.provider_id,
      note: note.note,
      starts_at: note.starts_at.iso8601,
      ends_at: note.ends_at.iso8601
    }
  end

  def calendar_note_props(note)
    {
      id: note.id,
      note: note.note,
      starts_at: note.starts_at.iso8601,
      ends_at: note.ends_at.iso8601,
      done: note.done
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
      },
      # N3 — end-of-appointment bullet summary surfaced for AppointmentShow.
      summary: appointment.summary_generated_at ? {
        decisions:         appointment.summary_decisions_text,
        patient_questions: appointment.summary_patient_questions,
        estimate_intent:   appointment.summary_estimate_intent_text,
        generated_at:      appointment.summary_generated_at.iso8601
      } : nil
    )
  end

  # P9.4 — start a scribe session for this appointment only if one isn't
  # already recording. Returns the session (truthy) on success, nil if
  # idempotent skip or rescued. Never raises.
  def maybe_start_scribe(appointment)
    if ScribeSession.where(appointment_id: appointment.id, status: "recording").exists?
      return nil
    end
    ScribeSession.start_for(appointment)
  rescue StandardError => e
    Rails.logger.warn("[AppointmentsController#set_status] scribe auto-start failed: #{e.message}")
    nil
  end

  # N3 — Generate the end-of-appointment bullet summary. Skipped if
  # there's no transcript yet (e.g. clinician completed manually without
  # any scribe input), or if a summary already exists for this appointment.
  def maybe_summarise(appointment)
    return nil if appointment.summary_generated_at.present?
    AppointmentSummaryService.summarise!(appointment)
  rescue StandardError => e
    Rails.logger.warn("[AppointmentsController#set_status] summary failed: #{e.message}")
    nil
  end

  def expire_appointment_caches!
    expire_dev_page_cache("appointments/index")
    expire_dev_page_cache("appointments/calendar")
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
