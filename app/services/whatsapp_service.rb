require "net/http"
require "base64"

class WhatsappService
  class Error < StandardError; end

  # Supported MIME types for Claude document API.
  SUPPORTED_MEDIA_TYPES = %w[application/pdf image/jpeg image/png image/gif image/webp].freeze

  # Payloads sent by WhatsApp quick-reply buttons in the confirmation request.
  # When a patient taps a button Twilio delivers these as the inbound Body.
  BUTTON_CONFIRM_PAYLOAD    = "CONFIRM APPOINTMENT".freeze
  BUTTON_RESCHEDULE_PAYLOAD = "RESCHEDULE APPOINTMENT".freeze

  def initialize
    @ai = nil
    @templates = nil
  end

  # Extract media attachment metadata from Twilio webhook params.
  # Returns an array of { url:, content_type: } hashes (one per media item).
  # Only includes MIME types the Claude API can process.
  def self.extract_media_attachments(twilio_params)
    num_media = twilio_params["NumMedia"].to_i
    return [] if num_media.zero?

    (0...num_media).filter_map do |i|
      url = twilio_params["MediaUrl#{i}"]
      content_type = twilio_params["MediaContentType#{i}"]
      next unless url.present? && SUPPORTED_MEDIA_TYPES.include?(content_type)

      { url: url, content_type: content_type }
    end
  end

  # Main entry point: handle an incoming WhatsApp message.
  # Returns { response:, intent:, entities: }
  def handle_incoming(from:, message:, twilio_params: {}, media_attachments: [])
    patient = find_or_create_patient(from)
    conversation = find_or_create_conversation(patient)

    # Detect and persist language from the first message
    detect_and_persist_language(conversation, message)

    # Button-reply fast path — intercepts quick-reply payloads before the AI
    # so "CONFIRM APPOINTMENT" / "RESCHEDULE APPOINTMENT" never waste an API call.
    button_result = build_button_payload_result(message: message, conversation: conversation)
    if button_result
      persist_exchange(conversation, message, button_result[:response])
      handle_intent(button_result, patient, conversation)
      return button_result
    end

    fast_path_result = build_local_result(message: message, conversation: conversation)

    if fast_path_result
      persist_exchange(conversation, message, fast_path_result[:response])
      handle_intent(fast_path_result, patient, conversation)
      return fast_path_result
    end

    # Process through AI brain
    downloaded = download_media_attachments(media_attachments)

    result = ai_service.process_message(
      message: message,
      conversation: conversation,
      patient: patient,
      media_attachments: downloaded
    )

    # Route based on detected intent
    handle_intent(result, patient, conversation)

    # Persist the exchange after intent handling so the stored response
    # reflects any rewrite that handle_intent may have applied (e.g.
    # booking-claim rewrites, after-hours blocks, nil on successful booking).
    persist_exchange(conversation, message, result[:response]) if conversation

    result
  rescue AiService::Error => e
    Rails.logger.warn("[WhatsApp] AI unavailable, using fallback response: #{e.message}")

    fallback_result = build_fallback_result(message: message, conversation: conversation)

    persist_exchange(conversation, message, fallback_result[:response]) if conversation

    fallback_result
  end

  private

  # --- Patient Management ---

  def find_or_create_patient(phone)
    Patient.find_or_create_by!(phone: normalize_phone(phone)) do |p|
      p.first_name = "WhatsApp"
      p.last_name = "Patient"
    end
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error("[WhatsApp] Failed to find/create patient for #{phone}: #{e.message}")
    # Try find again in case of race condition
    Patient.find_by!(phone: normalize_phone(phone))
  end

  def find_or_create_conversation(patient)
    # Reuse active conversation if one exists (within last 24 hours)
    conversation = patient.conversations
      .where(channel: "whatsapp", status: "active")
      .where("updated_at > ?", 24.hours.ago)
      .order(updated_at: :desc)
      .first

    conversation || patient.conversations.create!(
      channel: "whatsapp",
      status: "active",
      messages: [],
      started_at: Time.current,
      language: patient.preferred_language.presence
    )
  end

  # --- Intent Routing ---

  def handle_intent(result, patient, conversation)
    case result[:intent]
    when "book"
      handle_booking(result, patient, conversation)
    when "reschedule"
      handle_reschedule(result, patient, conversation)
    when "cancel"
      handle_cancellation(result, patient, conversation)
    when "confirm"
      handle_confirmation(patient)
    when "confirm_upcoming"
      handle_upcoming_confirmation(patient)
    when "urgent"
      handle_urgent(patient, conversation)
    end
  rescue StandardError => e
    Rails.logger.error("[WhatsApp] Intent handling error (#{result[:intent]}): #{e.message}")
    # Don't re-raise — the AI response is already set, intent handling is best-effort
  end

  # --- Booking Flow ---
  #
  # IMPORTANT — the AI generates `result[:response]` *before* this
  # handler runs, so the bot will happily compose "Perfect! I have
  # you booked..." text even when no Appointment row gets persisted
  # (slot mismatch, Google API error, missing credentials, etc).
  # We mutate `result[:response]` in place when the booking didn't
  # actually land so the controller's TwiML reply matches reality.
  # The hash is shared by reference with WhatsappController, which
  # reads `result[:response]` *after* this handler returns.

  BOOKING_FAILED_FALLBACK = {
    "en" => "Sorry — I couldn't lock that slot in. It may have just been " \
            "taken, or our calendar isn't reachable right now. Could you " \
            "try a different time, or call the practice directly?",
    "af" => "Jammer — ek kon nie daardie tyd vasmaak nie. Dit is dalk pas " \
            "geneem, of ons kalender is nie nou bereikbaar nie. Kan jy " \
            "'n ander tyd probeer, of bel die praktyk direk?"
  }.freeze

  AFTER_HOURS_TODAY_BLOCKED = {
    "en" => "Hi there! Our practice is currently closed (after hours). 🕐\n\n" \
            "🚨 *Dental emergency?* Contact Dr Chalita directly: *071 884 3204*\n\n" \
            "For non-urgent bookings, you're welcome to book for the next working day — " \
            "just send me your preferred date and time and we'll confirm first thing when we open. 😊",
    "af" => "Hallo! Ons praktyk is tans gesluit (na-ure). 🕐\n\n" \
            "🚨 *Tandheelkundige noodgeval?* Kontak Dr Chalita direk: *071 884 3204*\n\n" \
            "Vir nie-dringende besprekings kan jy gerus vir die volgende werksdag bespreek — " \
            "stuur net jou voorkeur datum en tyd en ons bevestig sodra ons oopmaak. 😊"
  }.freeze

  EMERGENCY_PHONE = "071 884 3204".freeze

  PRACTICE_ADDRESS = "Unit 2, Amorosa Office Park, Corner of Doreen Road & Lawrence Rd, Amorosa, Roodepoort, Johannesburg, 2040".freeze

  PRACTICE_MAP_LINK = "https://maps.app.goo.gl/3iHKg7AMa8qRcfLf6".freeze

  PRACTICE_DIRECTIONS = "From Hendrik Potgieter Rd: Turn onto Doreen Rd, we are on your left-hand side at the second robot. From CR Swart Rd: Turn onto Doreen Rd, we are on your right-hand side at the first robot.".freeze

  # Phrases that indicate the AI's free-text reply is *claiming* a
  # confirmed booking. If we see any of these but didn't actually
  # persist an Appointment, we must rewrite the reply — otherwise the
  # bot lies to the patient. Kept deliberately broad; false positives
  # here just mean we replace a vague AI message with a clearer one.
  # Canvas Section 9: Appointment durations by treatment type
  APPOINTMENT_DURATIONS = {
    "check-up"              => 45.minutes,
    "check up"              => 45.minutes,
    "checkup"               => 45.minutes,
    "examination"           => 45.minutes,
    "cosmetic consultation" => 45.minutes,
    "cosmetic"              => 45.minutes
  }.freeze
  DEFAULT_DURATION = 30.minutes

  RESCHEDULE_REJECTED = {
    "en" => "Sorry — that slot isn't available or falls outside our working hours. Would you like to try a different day or time?",
    "af" => "Jammer — daardie tyd is nie beskikbaar nie of val buite ons werksure. Wil jy 'n ander dag of tyd probeer?"
  }.freeze

  BOOKING_CLAIM_PHRASES = [
    # English
    "i have you booked",
    "you're booked",
    "youre booked",
    "you are booked",
    "you're confirmed",
    "you are confirmed",
    "appointment is confirmed",
    "appointment is booked",
    "i've booked",
    "ive booked",
    "i've scheduled",
    "ive scheduled",
    "all set for",
    "see you on",
    "see you at",
    # Afrikaans
    "jy is bespreek",
    "afspraak is bevestig",
    "afspraak is bespreek",
    "ek het jou bespreek",
    "ek het jou ingeskryf",
    "sien jou op",
    "sien jou om",
    "alles is reg vir"
  ].freeze

  def handle_booking(result, patient, conversation)
    entities = result[:entities] || {}
    date = entities[:date]
    time = entities[:time]
    lang = conversation&.language || "en"

    Rails.logger.info(
      "[WhatsApp] handle_booking intent=book date=#{date.inspect} " \
      "time=#{time.inspect} treatment=#{entities[:treatment].inspect} " \
      "name=#{entities[:name].inspect}"
    )

    # Update the patient's name if they provided one and they still
    # have the placeholder "WhatsApp Patient" name.
    update_patient_name(patient, entities[:name]) if entities[:name].present?

    booking_result = nil
    if date.present? && time.present?
      booking_result = attempt_booking(patient, date, time, entities[:treatment], language: lang)
    end

    # After-hours booking for today — blocked, rewrite response
    if booking_result == :after_hours_today
      lang = conversation&.language || "en"
      result[:response] = AFTER_HOURS_TODAY_BLOCKED[lang] || AFTER_HOURS_TODAY_BLOCKED["en"]
      return
    end

    if booking_result.is_a?(Appointment)
      # Confirmation was already sent via send_booking_confirmation_message.
      # Clear the AI's response so the job doesn't send a second conflicting message.
      result[:response] = nil
      return
    end

    # We did NOT persist an Appointment — either because the classifier
    # didn't normalize the date/time (relative phrases like "Friday")
    # or because attempt_booking failed. If the AI's free text is
    # *claiming* a booking, rewrite it so the controller's TwiML reply
    # matches reality. If it's still gathering info ("what day works?"),
    # leave it alone.
    if booking_claim?(result[:response])
      Rails.logger.warn(
        "[WhatsApp] AI claimed a booking but no Appointment was persisted; " \
        "rewriting response. date=#{date.inspect} time=#{time.inspect}"
      )
      lang = conversation&.language || "en"
      result[:response] = BOOKING_FAILED_FALLBACK[lang] || BOOKING_FAILED_FALLBACK["en"]
    end
  end

  def booking_claim?(response)
    return false if response.blank?

    text = response.downcase
    BOOKING_CLAIM_PHRASES.any? { |phrase| text.include?(phrase) }
  end

  # Returns the persisted Appointment on success, or nil on any
  # failure. Never raises — the caller relies on the nil sentinel.
  #
  # The local Appointment table is the source of truth — the in-app
  # FullCalendar reads from it directly. Google Calendar is a
  # best-effort secondary sync; if creds aren't set or the API
  # errors, we still persist locally so the booking shows up in
  # the in-app calendar. The previous implementation made Google
  # the gatekeeper, so any creds/API issue silently swallowed the
  # booking with no row written and no error surfaced.
  def attempt_booking(patient, date, time, treatment, language: "en")
    start_time = Time.zone.parse("#{date} #{time}")
    duration = duration_for_treatment(treatment)
    end_time = start_time + duration
    reason = treatment&.capitalize || "Consultation"

    unless start_time > Time.current
      Rails.logger.info("[WhatsApp] Booking rejected: slot is in the past (#{start_time})")
      return nil
    end

    after_hours = !slot_within_working_hours?(start_time, end_time)
    if after_hours && start_time.to_date == Date.current
      # After hours + same day = blocked (can't confirm in time)
      Rails.logger.info("[WhatsApp] Booking rejected: after hours for today (#{start_time})")
      return :after_hours_today
    end

    if after_hours
      Rails.logger.info("[WhatsApp] After-hours booking for future date — pending confirmation (#{start_time})")
    end

    if slot_conflicts_locally?(start_time, end_time)
      Rails.logger.info("[WhatsApp] Booking rejected: conflicts with existing appointment (#{start_time})")
      return nil
    end

    appointment = patient.appointments.create!(
      start_time: start_time,
      end_time: end_time,
      reason: reason,
      status: after_hours ? :pending_confirmation : :scheduled
    )

    # Create a confirmation log so the reminders page tracks this
    # booking from the moment it's created. The outcome is nil
    # until the patient replies to the WhatsApp confirmation.
    appointment.confirmation_logs.create!(
      method: "whatsapp",
      outcome: nil,
      attempts: 1,
      flagged: false
    )

    sync_to_google_calendar(appointment, patient, reason)
    send_confirmation_template(patient, appointment, after_hours: after_hours, language: language)
    send_confirmation_email(appointment)
    send_confirmation_sms(appointment)
    appointment
  rescue StandardError => e
    Rails.logger.error("[WhatsApp] Booking failed: #{e.class}: #{e.message}")
    nil
  end

  # Working-hours check against DoctorSchedule. Rejects bookings
  # outside the doctor's hours, on closed days, or that overlap
  # the lunch break.
  def slot_within_working_hours?(start_time, end_time)
    schedule = DoctorSchedule.for_day(start_time.wday)
    return false unless schedule

    schedule.working?(start_time) && schedule.working?(end_time - 1.minute)
  end

  # Local conflict check — any existing non-cancelled appointment
  # whose time range overlaps the requested slot.
  # Pass exclude_appointment_id when rescheduling to avoid the
  # appointment conflicting with its own current slot.
  def slot_conflicts_locally?(start_time, end_time, exclude_appointment_id: nil)
    query = Appointment
      .where.not(status: :cancelled)
      .where("start_time < ? AND end_time > ?", end_time, start_time)
    query = query.where.not(id: exclude_appointment_id) if exclude_appointment_id
    query.exists?
  end

  # Best-effort Google Calendar sync. Failure here does NOT roll
  # back the local Appointment — the patient is still booked in
  # the in-app calendar. If creds are missing or the API errors,
  # we log and move on. A future job can backfill google_event_id
  # for unsynced appointments.
  def sync_to_google_calendar(appointment, patient, reason)
    calendar = GoogleCalendarService.new
    event_id = calendar.create_event(
      patient: patient,
      start_time: appointment.start_time,
      end_time: appointment.end_time,
      reason: reason
    )
    appointment.update_column(:google_event_id, event_id) if event_id
  rescue StandardError => e
    Rails.logger.warn("[WhatsApp] Google Calendar sync skipped: #{e.class}: #{e.message}")
  end

  # --- Reschedule Flow ---

  def handle_reschedule(result, patient, conversation)
    entities = result[:entities] || {}
    appointments = patient.appointments.upcoming

    return if appointments.empty?

    # Bail early only when we have neither a date nor a time.
    # A time-only response ("same time at 2pm") is valid — we'll
    # find the next available date for that time below.
    return unless entities[:date].present? || entities[:time].present?

    appointment = appointments.first
    duration = appointment.end_time - appointment.start_time
    lang = conversation&.language || "en"

    new_start = if entities[:date].present? && entities[:time].present?
      Time.zone.parse("#{entities[:date]} #{entities[:time]}")
    elsif entities[:time].present?
      # Patient gave a time but no specific date — find the next available
      # working day where that time slot is free.
      next_date = next_available_date_for_time(entities[:time], duration)
      unless next_date
        result[:response] = RESCHEDULE_REJECTED[lang] || RESCHEDULE_REJECTED["en"]
        return
      end
      Time.zone.parse("#{next_date} #{entities[:time]}")
    else
      # Date only, no time — ask the AI to gather the time; bail for now
      return
    end

    new_end = new_start + duration

    # Guardrail: new slot must be in the future
    unless new_start > Time.current
      result[:response] = RESCHEDULE_REJECTED[lang] || RESCHEDULE_REJECTED["en"]
      return
    end

    # Guardrail: new slot must be within working hours
    unless slot_within_working_hours?(new_start, new_end)
      result[:response] = RESCHEDULE_REJECTED[lang] || RESCHEDULE_REJECTED["en"]
      Rails.logger.info("[WhatsApp] Reschedule rejected: outside working hours (#{new_start})")
      return
    end

    # Guardrail: new slot must not conflict with another appointment.
    # Exclude the appointment being moved — it's vacating the old slot.
    if slot_conflicts_locally?(new_start, new_end, exclude_appointment_id: appointment.id)
      result[:response] = RESCHEDULE_REJECTED[lang] || RESCHEDULE_REJECTED["en"]
      Rails.logger.info("[WhatsApp] Reschedule rejected: slot conflict (#{new_start})")
      return
    end

    # Local record is source of truth — update regardless of Google Calendar state
    appointment.update!(
      start_time: new_start,
      end_time: new_end,
      status: :scheduled
    )

    # Best-effort Google Calendar sync — failure does not roll back the local update
    if appointment.google_event_id
      begin
        GoogleCalendarService.new.reschedule_appointment(
          appointment.google_event_id,
          new_start: new_start
        )
      rescue StandardError => e
        Rails.logger.warn("[WhatsApp] Google Calendar reschedule sync skipped: #{e.message}")
      end
    end

    send_reschedule_template(patient, appointment)
  rescue StandardError => e
    Rails.logger.error("[WhatsApp] Reschedule failed: #{e.message}")
  end

  # --- Cancellation Flow ---

  def handle_cancellation(result, patient, conversation)
    appointments = patient.appointments.upcoming

    return if appointments.empty?

    appointment = appointments.first
    reason_category = extract_cancellation_reason(result)

    # Cancel locally first — Google Calendar sync is best-effort
    appointment.cancelled!

    if appointment.google_event_id
      begin
        GoogleCalendarService.new.cancel_appointment(
          appointment.google_event_id,
          reason_category: reason_category,
          reason_details: "Cancelled via WhatsApp"
        )
      rescue StandardError => e
        Rails.logger.warn("[WhatsApp] Google Calendar cancel sync skipped: #{e.message}")
      end
    end

    send_cancellation_template(patient, appointment)
  rescue StandardError => e
    Rails.logger.error("[WhatsApp] Cancellation failed: #{e.message}")
  end

  # --- Confirmation Flow ---

  def handle_confirmation(patient)
    appointment = patient.appointments
      .where(status: :scheduled)
      .where(start_time: Date.current.all_day)
      .first

    return unless appointment

    appointment.confirmed!

    appointment.confirmation_logs.create!(
      method: "whatsapp",
      outcome: "confirmed",
      attempts: 1,
      flagged: false
    )
  end

  # Confirms the patient's next upcoming appointment (used for button-reply
  # confirmations where the appointment may be tomorrow, not today).
  # The existing handle_confirmation targets same-day appointments for the
  # voice/manual-reply flow and is left unchanged.
  def handle_upcoming_confirmation(patient)
    appointment = patient.appointments
      .where(status: :scheduled)
      .where("start_time > ?", Time.current)
      .order(:start_time)
      .first

    return unless appointment

    appointment.confirmed!

    appointment.confirmation_logs.create!(
      method:   "whatsapp",
      outcome:  "confirmed",
      attempts: 1,
      flagged:  false,
      notes:    "Confirmed via WhatsApp button"
    )

    mark_appointment_confirmed_on_calendar(appointment)
  end

  # Detects whether the inbound message is a quick-reply button tap and
  # returns a pre-built result hash, bypassing the AI entirely.
  # Returns nil for any other message so the normal flow continues.
  def build_button_payload_result(message:, conversation:)
    lang   = conversation&.language || "en"
    body   = message.to_s.strip.upcase

    if body == BUTTON_CONFIRM_PAYLOAD
      response = lang == "af" ?
        "Uitstekend! Jou afspraak is bevestig. Ons sien jou môre! 😊" :
        "Great! Your appointment is confirmed. We'll see you tomorrow! 😊"
      { response: response, intent: "confirm_upcoming", entities: {} }

    elsif body == BUTTON_RESCHEDULE_PAYLOAD
      response = lang == "af" ?
        "Geen probleem! Stuur asseblief jou voorkeur datum en tyd en ons sal dit reël." :
        "No problem! Please send your preferred date and time and we'll arrange that for you."
      { response: response, intent: "reschedule", entities: {} }
    end
  end

  # Best-effort Google Calendar update when appointment is confirmed.
  def mark_appointment_confirmed_on_calendar(appointment)
    return unless appointment.google_event_id

    GoogleCalendarService.new.confirm_appointment(appointment.google_event_id)
  rescue StandardError => e
    Rails.logger.warn("[WhatsApp] Google Calendar confirm sync skipped: #{e.message}")
  end

  # --- Urgent Flow ---

  def handle_urgent(patient, conversation)
    # Flag for immediate follow-up
    send_flagged_alert(patient, "URGENT: Patient reported dental emergency via WhatsApp")
  end

  # --- Template Sending (best-effort) ---

  def send_confirmation_template(patient, appointment, after_hours: false, language: "en")
    # Send detailed booking confirmation with directions via free-form
    # message (within the 24-hour service window since the patient
    # just messaged us). Falls back to the Twilio template if the
    # free-form send fails.
    send_booking_confirmation_message(patient, appointment, after_hours: after_hours, language: language)
  rescue StandardError => e
    Rails.logger.warn("[WhatsApp] Booking confirmation message failed, trying template: #{e.message}")
    begin
      template_service&.send_confirmation(patient, appointment)
    rescue WhatsappTemplateService::Error => te
      Rails.logger.warn("[WhatsApp] Template fallback also failed: #{te.message}")
    end
  end

  # Sends the branded booking confirmation message with appointment
  # details and practice directions. Uses the free-form `send_text`
  # method since the patient is within the 24-hour service window.
  # Bilingual: responds in Afrikaans when language == "af".
  def send_booking_confirmation_message(patient, appointment, after_hours: false, language: "en")
    day_name  = appointment.start_time.strftime("%A")
    date_str  = appointment.start_time.strftime("%-d %B %Y")
    time_str  = appointment.start_time.strftime("%H:%M")
    is_new = patient.auto_created_placeholder_profile?

    body = if language == "af"
      after_hours_notice = after_hours ?
        "\n\n⏳ Hierdie bespreking is na ure gemaak. Ons sal jou afspraak bevestig sodra die praktyk môreoggend oopmaak." : ""
      new_patient_addon = is_new ?
        "\n\nOnthou dat ons nie direk van mediesefonds eis nie. Pasiënte betaal by die praktyk en kan daarna terugeis met die staat wat ons verskaf.\n\nKom asseblief 10 minute vroeg aan sodat ons jou lêer kan voltooi." : ""

      <<~MSG.strip
        Jou afspraak is bespreek vir #{day_name}, #{date_str} om #{time_str}.#{after_hours_notice}

        #{PRACTICE_ADDRESS}
        Google Maps: #{PRACTICE_MAP_LINK}

        Aanwysings: #{PRACTICE_DIRECTIONS}#{new_patient_addon}

        As jy iets wil verander, antwoord net hier.
      MSG
    else
      after_hours_notice = after_hours ?
        "\n\n⏳ This booking was made after hours. We'll confirm your appointment first thing in the morning once we verify the slot is available." : ""
      new_patient_addon = is_new ?
        "\n\nA reminder that we do not claim directly from medical aid. Patients pay at the practice and can then claim back using the statement we provide.\n\nPlease arrive 10 minutes early so we can complete your patient file." : ""

      <<~MSG.strip
        Your appointment is booked for #{day_name}, #{date_str} at #{time_str}.#{after_hours_notice}

        #{PRACTICE_ADDRESS}
        Google Maps: #{PRACTICE_MAP_LINK}

        Directions: #{PRACTICE_DIRECTIONS}#{new_patient_addon}

        If you need to change anything, just reply here.
      MSG
    end

    template_service&.send_text(patient.phone, body)
  end

  def time_greeting
    hour = Time.current.hour
    if hour < 12
      "Good morning"
    elsif hour < 17
      "Good afternoon"
    else
      "Good evening"
    end
  end

  def send_reschedule_template(patient, appointment)
    template_service&.send_reschedule(patient, appointment)
  rescue WhatsappTemplateService::Error => e
    Rails.logger.warn("[WhatsApp] Template send failed: #{e.message}")
  end

  def send_cancellation_template(patient, appointment)
    template_service&.send_cancellation(patient, appointment)
  rescue WhatsappTemplateService::Error => e
    Rails.logger.warn("[WhatsApp] Template send failed: #{e.message}")
  end

  def send_confirmation_email(appointment)
    AppointmentMailer.confirmation(appointment).deliver_later
  rescue StandardError => e
    Rails.logger.warn("[WhatsApp] Confirmation email failed: #{e.message}")
  end

  def send_confirmation_sms(appointment)
    SmsService.send_confirmation(appointment)
  rescue StandardError => e
    Rails.logger.warn("[WhatsApp] Confirmation SMS failed: #{e.message}")
  end

  def send_flagged_alert(patient, reason)
    template_service&.send_flagged_alert(patient, reason)
  rescue WhatsappTemplateService::Error => e
    Rails.logger.warn("[WhatsApp] Flagged alert send failed: #{e.message}")
  end

  # --- Helpers ---

  # Updates the patient's first/last name if they still have the
  # placeholder "WhatsApp Patient" name and the AI extracted a real
  # name from the conversation. This means the patient record,
  # appointments list, and dashboard all show the actual name
  # instead of the generic placeholder.
  def update_patient_name(patient, full_name)
    return unless patient.auto_created_placeholder_profile? ||
                  (patient.first_name == "WhatsApp" && patient.last_name == "Patient")

    parts = full_name.to_s.strip.split(/\s+/, 2)
    return if parts.empty?

    first = parts[0]
    last  = parts[1] || patient.last_name

    patient.update(first_name: first, last_name: last)
    Rails.logger.info("[WhatsApp] Updated patient name: #{patient.phone} → #{first} #{last}")
  rescue StandardError => e
    Rails.logger.warn("[WhatsApp] Failed to update patient name: #{e.message}")
  end

  def duration_for_treatment(treatment)
    return DEFAULT_DURATION if treatment.blank?

    key = treatment.downcase.strip
    APPOINTMENT_DURATIONS[key] || DEFAULT_DURATION
  end

  def normalize_phone(phone)
    phone.gsub(/\s+/, "").then { |p| p.start_with?("+") ? p : "+#{p}" }
  end

  def extract_cancellation_reason(result)
    # Try to infer reason from the conversation context
    message = result[:response]&.downcase || ""
    if message.include?("cost") || message.include?("expensive") || message.include?("price")
      "cost"
    elsif message.include?("fear") || message.include?("scared") || message.include?("nervous")
      "fear"
    elsif message.include?("time") || message.include?("busy") || message.include?("schedule")
      "timing"
    elsif message.include?("transport") || message.include?("far") || message.include?("travel")
      "transport"
    else
      "other"
    end
  end

  FALLBACK_BUSY = {
    "en" => "I'm sorry, our system is a bit busy right now. Please send your preferred day and time, and our team will follow up as soon as possible.",
    "af" => "Jammer, ons stelsel is tans effens besig. Stuur asseblief jou voorkeur dag en tyd, en ons span sal so gou moontlik opvolg."
  }.freeze

  URGENT_FAST_PATH = {
    "en" => "I'm sorry you're dealing with that. If this is an emergency, please contact Dr Chalita directly at #{EMERGENCY_PHONE} so we can assist you as quickly as possible.",
    "af" => "Ek is jammer om dit te hoor. As dit 'n noodgeval is, kontak Dr Chalita direk by #{EMERGENCY_PHONE} sodat ons jou so gou moontlik kan help."
  }.freeze

  def build_fallback_result(message:, conversation:)
    # First try urgent (always immediate)
    result = build_local_result(message: message, conversation: conversation)
    return result if result

    lang = conversation&.language || "en"
    msg_lower = message.downcase

    if msg_lower.match?(/\b(hours?|open|closed|time|schedule|ure|oopmaak|tyd)\b/)
      return {
        response: AiService.dynamic_hours,
        intent: "faq",
        entities: {}
      }
    end

    if msg_lower.match?(/\b(price|cost|how much|consultation|cleaning|prys|koste|hoeveel)\b/)
      return {
        response: "Consultation: #{AiService::PRICING['consultation']} | Cleaning: #{AiService::PRICING['cleaning']}",
        intent: "faq",
        entities: {}
      }
    end

    {
      response: FALLBACK_BUSY[lang] || FALLBACK_BUSY["en"],
      intent: "book",
      entities: {}
    }
  end

  def build_local_result(message:, conversation:)
    # Only use fast path for urgent/emergency (always immediate)
    # Don't use for book/reschedule/cancel (need multi-turn with AI)
    lang = conversation&.language || "en"
    if message.downcase.match?(/\b(pain|urgent|emergency|swollen|bleeding|pyn|noodgeval|geswel|bloeding)\b/)
      return {
        response: URGENT_FAST_PATH[lang] || URGENT_FAST_PATH["en"],
        intent: "urgent",
        entities: {}
      }
    end

    # For other intents, let Claude handle multi-turn conversation
    nil
  end

  def persist_exchange(conversation, user_message, assistant_message)
    conversation.add_messages([
      { role: "user", content: user_message },
      { role: "assistant", content: assistant_message }
    ])
  end

  # --- Language Detection ---

  # Common Afrikaans words and patterns for fast detection.
  # We check against these before falling back to a default of English.
  AFRIKAANS_MARKERS = %w[
    hallo goeie môre middag aand oggend
    ek jy hy sy ons julle hulle
    het kan sal wil moet
    graag asseblief dankie baie seker
    dokter afspraak bespreek tyd
    wanneer hoeveel kos dit maak besig vandag
    vanaand gister laasweek volgende
    maandag dinsdag woensdag donderdag vrydag
    januarie februarie maart april mei junie julie augustus
    september oktober november desember
    ja nee reg beter nie ook
    naam sê praat
    pyn tand mond mondhigiëne
    nuwe pasiënt bestaande
    betaling mediesefonds kontant
    adres rigting parkering
    totsiens groete
    hierdie daai wat waar waarom
  ].freeze

  # Detect language from the message text and persist on the conversation and patient.
  # Only runs detection if the conversation doesn't already have a language set,
  # OR if the user clearly switches language mid-conversation.
  # Also keeps patient.preferred_language in sync for cross-conversation memory.
  def detect_and_persist_language(conversation, message)
    detected = detect_language(message)
    patient = conversation.patient

    if conversation.language.blank?
      conversation.update_column(:language, detected)
      Rails.logger.info("[WhatsApp] Language detected: #{detected} (first message)")
    elsif detected != conversation.language && strong_language_signal?(message, detected)
      conversation.update_column(:language, detected)
      Rails.logger.info("[WhatsApp] Language switched to: #{detected}")
    end

    # Persist preferred language on the patient record if it's changed or unset.
    # This gives us cross-conversation language memory.
    current_lang = conversation.language
    if patient.preferred_language != current_lang
      patient.update_column(:preferred_language, current_lang)
    end
  rescue StandardError => e
    Rails.logger.warn("[WhatsApp] detect_and_persist_language failed: #{e.message}")
  end

  # Simple heuristic language detection: count Afrikaans marker words.
  # Returns "af" or "en".
  def detect_language(message)
    words = message.downcase.gsub(/[^\w\s']/, "").split
    af_count = words.count { |w| AFRIKAANS_MARKERS.include?(w) }

    # If ≥2 Afrikaans markers or ≥30% of words are Afrikaans markers, classify as Afrikaans
    if af_count >= 2 || (words.length > 0 && af_count.to_f / words.length >= 0.3)
      "af"
    else
      "en"
    end
  end

  # Returns true if the message has a strong enough signal to justify switching
  # the conversation language (avoids flipping on borrowed words).
  def strong_language_signal?(message, detected_lang)
    words = message.downcase.gsub(/[^\w\s']/, "").split
    return false if words.length < 2

    if detected_lang == "af"
      af_count = words.count { |w| AFRIKAANS_MARKERS.include?(w) }
      af_count >= 3
    else
      # Switching to English: no Afrikaans markers at all
      af_count = words.count { |w| AFRIKAANS_MARKERS.include?(w) }
      af_count == 0 && words.length >= 3
    end
  end

  # --- Media Download ---

  # Download all media attachments from Twilio, returning an array of
  # { content_type:, data: (base64) } hashes ready for the Claude API.
  # Individual failures are swallowed — the message still processes.
  def download_media_attachments(attachments)
    return [] if attachments.blank?

    attachments.filter_map do |attachment|
      download_media(attachment[:url], attachment[:content_type])
    rescue StandardError => e
      Rails.logger.warn("[WhatsApp] Media download failed (#{attachment[:url]}): #{e.message}")
      nil
    end
  end

  # Download a single Twilio media URL using Basic Auth credentials.
  # Returns { content_type:, data: (base64 string) } or raises on failure.
  def download_media(url, content_type)
    account_sid = ENV.fetch("TWILIO_ACCOUNT_SID")
    auth_token  = ENV.fetch("TWILIO_AUTH_TOKEN")

    uri = URI.parse(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = 10
    http.read_timeout = 30

    request = Net::HTTP::Get.new(uri.request_uri)
    request.basic_auth(account_sid, auth_token)

    response = http.request(request)
    raise Error, "HTTP #{response.code} downloading media from Twilio" unless response.is_a?(Net::HTTPSuccess)

    { content_type: content_type, data: Base64.strict_encode64(response.body) }
  end

  # Find the next working day (up to 14 days ahead) where the requested
  # time string ("14:00") is available for `duration` minutes without
  # conflicting with existing appointments.
  def next_available_date_for_time(time_str, duration = DEFAULT_DURATION)
    date = Date.current
    14.times do
      date = date.next_day
      schedule = DoctorSchedule.for_day(date.wday)
      next unless schedule

      candidate_start = Time.zone.parse("#{date} #{time_str}")
      candidate_end   = candidate_start + duration

      next unless candidate_start > Time.current
      next unless schedule.working?(candidate_start) && schedule.working?(candidate_end - 1.minute)
      next if slot_conflicts_locally?(candidate_start, candidate_end)

      return date
    end
    nil
  rescue StandardError => e
    Rails.logger.warn("[WhatsApp] next_available_date_for_time failed: #{e.message}")
    nil
  end

  def ai_service
    @ai ||= AiService.new
  end

  def template_service
    @templates ||= begin
      WhatsappTemplateService.new
    rescue StandardError
      # Template service may fail if Twilio creds aren't set (dev/test)
      nil
    end
  end
end
