class GoogleCalendarService
  SLOT_DURATION = 30.minutes
  CALENDAR_ID = ENV.fetch("GOOGLE_CALENDAR_ID", "primary")

  class Error < StandardError; end
  class NotFoundError < Error; end

  def initialize
    @service = Google::Apis::CalendarV3::CalendarService.new
    @service.authorization = authorization
    @service.request_options.timeout_sec = 15
    @service.request_options.open_timeout_sec = 5
  rescue Error
    raise
  rescue StandardError => e
    raise Error, "Google Calendar initialization failed: #{e.message}"
  end

  # Returns available 30-minute slots for a given date,
  # respecting doctor schedule and existing bookings.
  def available_slots(date)
    date = Date.parse(date.to_s)
    schedule = DoctorSchedule.for_day(date.wday)
    return [] unless schedule

    busy_periods = fetch_busy_periods(date)
    generate_slots(date, schedule, busy_periods)
  end

  # Books an appointment on Google Calendar and creates local record.
  def book_appointment(patient:, start_time:, end_time: nil, reason: nil)
    end_time ||= start_time + SLOT_DURATION
    start_time = Time.zone.parse(start_time.to_s) if start_time.is_a?(String)
    end_time = Time.zone.parse(end_time.to_s) if end_time.is_a?(String)

    event = Google::Apis::CalendarV3::Event.new(
      summary: "Dental Appointment — #{patient.full_name}",
      description: build_description(patient, reason),
      start: event_datetime(start_time),
      end: event_datetime(end_time),
      reminders: { use_default: false }
    )

    result = @service.insert_event(CALENDAR_ID, event)

    patient.appointments.create!(
      start_time: start_time,
      end_time: end_time,
      google_event_id: result.id,
      reason: reason,
      status: :scheduled
    )
  rescue Google::Apis::Error => e
    raise Error, "Failed to book appointment: #{e.message}"
  end

  # Finds appointments for a patient within a date range.
  def find_appointment(patient_phone, date_range: nil)
    patient = Patient.find_by!(phone: patient_phone)
    scope = patient.appointments.upcoming
    scope = scope.where(start_time: date_range) if date_range
    scope.to_a
  rescue ActiveRecord::RecordNotFound
    raise NotFoundError, "No patient found with phone #{patient_phone}"
  end

  # Reschedules an existing appointment to a new time.
  def reschedule_appointment(event_id, new_start:, new_end: nil)
    new_start = Time.zone.parse(new_start.to_s) if new_start.is_a?(String)
    new_end ||= new_start + SLOT_DURATION
    new_end = Time.zone.parse(new_end.to_s) if new_end.is_a?(String)

    event = @service.get_event(CALENDAR_ID, event_id)
    event.start = event_datetime(new_start)
    event.end = event_datetime(new_end)
    @service.update_event(CALENDAR_ID, event_id, event)

    appointment = Appointment.find_by!(google_event_id: event_id)
    appointment.update!(start_time: new_start, end_time: new_end, status: :rescheduled)
    appointment
  rescue Google::Apis::ClientError => e
    raise NotFoundError, "Event not found: #{e.message}" if e.status_code == 404
    raise Error, "Failed to reschedule: #{e.message}"
  end

  # Cancels an appointment on Google Calendar and updates local record.
  def cancel_appointment(event_id, reason_category: nil, reason_details: nil)
    @service.delete_event(CALENDAR_ID, event_id)

    appointment = Appointment.find_by!(google_event_id: event_id)
    appointment.cancelled!

    if reason_category.present?
      appointment.create_cancellation_reason!(
        reason_category: reason_category,
        details: reason_details
      )
    end

    appointment
  rescue Google::Apis::ClientError => e
    raise NotFoundError, "Event not found: #{e.message}" if e.status_code == 404
    raise Error, "Failed to cancel: #{e.message}"
  end

  private

  def authorization
    json_key = ENV.fetch("GOOGLE_SERVICE_ACCOUNT_JSON", nil)
    raise Error, "GOOGLE_SERVICE_ACCOUNT_JSON is not configured" if json_key.blank? || json_key == "{}"

    key_io = StringIO.new(json_key)
    Google::Auth::ServiceAccountCredentials.make_creds(
      json_key_io: key_io,
      scope: Google::Apis::CalendarV3::AUTH_CALENDAR
    )
  rescue JSON::ParserError => e
    raise Error, "GOOGLE_SERVICE_ACCOUNT_JSON contains invalid JSON: #{e.message}"
  end

  def fetch_busy_periods(date)
    time_min = date.beginning_of_day.iso8601
    time_max = date.end_of_day.iso8601

    request = Google::Apis::CalendarV3::FreeBusyRequest.new(
      time_min: time_min,
      time_max: time_max,
      items: [ { id: CALENDAR_ID } ]
    )

    response = @service.query_freebusy(request)
    calendar_busy = response.calendars[CALENDAR_ID]&.busy || []
    calendar_busy.map { |period| period.start..period.end }
  rescue Google::Apis::Error => e
    raise Error, "Failed to fetch availability: #{e.message}"
  end

  def generate_slots(date, schedule, busy_periods)
    slots = []
    zone = Time.zone || Time.find_zone("Africa/Johannesburg")

    day_start = zone.parse("#{date} #{schedule.start_time.strftime('%H:%M')}")
    day_end = zone.parse("#{date} #{schedule.end_time.strftime('%H:%M')}")

    break_start = schedule.break_start.present? ? zone.parse("#{date} #{schedule.break_start.strftime('%H:%M')}") : nil
    break_end = schedule.break_end.present? ? zone.parse("#{date} #{schedule.break_end.strftime('%H:%M')}") : nil

    current = day_start
    while current + SLOT_DURATION <= day_end
      slot_end = current + SLOT_DURATION

      on_break = break_start && break_end && current < break_end && slot_end > break_start
      busy = busy_periods.any? { |period| current < period.end && slot_end > period.begin }

      unless on_break || busy
        slots << { start_time: current, end_time: slot_end }
      end

      current += SLOT_DURATION
    end

    slots
  end

  def event_datetime(time)
    Google::Apis::CalendarV3::EventDateTime.new(
      date_time: time.iso8601,
      time_zone: "Africa/Johannesburg"
    )
  end

  def build_description(patient, reason)
    parts = [ "Patient: #{patient.full_name}", "Phone: #{patient.phone}" ]
    parts << "Reason: #{reason}" if reason.present?
    parts.join("\n")
  end
end
