class WhatsappService
  class Error < StandardError; end

  def initialize
    @ai = nil
    @templates = nil
  end

  # Main entry point: handle an incoming WhatsApp message.
  # Returns { response:, intent:, entities: }
  def handle_incoming(from:, message:, twilio_params: {})
    patient = find_or_create_patient(from)
    conversation = find_or_create_conversation(patient)

    fast_path_result = build_local_result(message: message, conversation: conversation)

    if fast_path_result
      persist_exchange(conversation, message, fast_path_result[:response])
      handle_intent(fast_path_result, patient, conversation)
      return fast_path_result
    end

    # Process through AI brain
    result = ai_service.process_message(
      message: message,
      conversation: conversation,
      patient: patient
    )

    # Route based on detected intent
    handle_intent(result, patient, conversation)

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
      started_at: Time.current
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

  BOOKING_FAILED_FALLBACK =
    "Sorry — I couldn't lock that slot in. It may have just been " \
    "taken, or our calendar isn't reachable right now. Could you " \
    "try a different time, or call the practice directly?".freeze

  PRACTICE_DIRECTIONS = <<~DIRS.strip
    Directions from Hendrik Potgieter Rd:
    Turn onto Doreen Rd,
    We are on your left-hand side at the second robot.

    Directions from CR Swart Rd:
    Turn onto Doreen Rd,
    We are on your right-hand side at the first robot.
  DIRS

  # Phrases that indicate the AI's free-text reply is *claiming* a
  # confirmed booking. If we see any of these but didn't actually
  # persist an Appointment, we must rewrite the reply — otherwise the
  # bot lies to the patient. Kept deliberately broad; false positives
  # here just mean we replace a vague AI message with a clearer one.
  BOOKING_CLAIM_PHRASES = [
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
    "see you at"
  ].freeze

  def handle_booking(result, patient, conversation)
    entities = result[:entities] || {}
    date = entities[:date]
    time = entities[:time]

    Rails.logger.info(
      "[WhatsApp] handle_booking intent=book date=#{date.inspect} " \
      "time=#{time.inspect} treatment=#{entities[:treatment].inspect} " \
      "name=#{entities[:name].inspect}"
    )

    # Update the patient's name if they provided one and they still
    # have the placeholder "WhatsApp Patient" name.
    update_patient_name(patient, entities[:name]) if entities[:name].present?

    appointment = nil
    if date.present? && time.present?
      appointment = attempt_booking(patient, date, time, entities[:treatment])
    end

    return if appointment

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
      result[:response] = BOOKING_FAILED_FALLBACK
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
  def attempt_booking(patient, date, time, treatment)
    start_time = Time.zone.parse("#{date} #{time}")
    end_time = start_time + GoogleCalendarService::SLOT_DURATION
    reason = treatment&.capitalize || "Consultation"

    unless start_time > Time.current
      Rails.logger.info("[WhatsApp] Booking rejected: slot is in the past (#{start_time})")
      return nil
    end

    unless slot_within_working_hours?(start_time, end_time)
      Rails.logger.info("[WhatsApp] Booking rejected: outside working hours (#{start_time})")
      return nil
    end

    if slot_conflicts_locally?(start_time, end_time)
      Rails.logger.info("[WhatsApp] Booking rejected: conflicts with existing appointment (#{start_time})")
      return nil
    end

    appointment = patient.appointments.create!(
      start_time: start_time,
      end_time: end_time,
      reason: reason,
      status: :scheduled
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
    send_confirmation_template(patient, appointment)
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
  def slot_conflicts_locally?(start_time, end_time)
    Appointment
      .where.not(status: :cancelled)
      .where("start_time < ? AND end_time > ?", end_time, start_time)
      .exists?
  end

  # Best-effort Google Calendar sync. Failure here does NOT roll
  # back the local Appointment — the patient is still booked in
  # the in-app calendar. If creds are missing or the API errors,
  # we log and move on. A future job can backfill google_event_id
  # for unsynced appointments.
  def sync_to_google_calendar(appointment, patient, reason)
    calendar = GoogleCalendarService.new
    synced = calendar.book_appointment(
      patient: patient,
      start_time: appointment.start_time,
      end_time: appointment.end_time,
      reason: reason
    )
    # `book_appointment` creates its own Appointment row — we don't
    # want a duplicate. Move its google_event_id onto our row and
    # delete the duplicate.
    if synced && synced.id != appointment.id
      appointment.update_column(:google_event_id, synced.google_event_id)
      synced.destroy
    end
  rescue StandardError => e
    Rails.logger.warn("[WhatsApp] Google Calendar sync skipped: #{e.class}: #{e.message}")
  end

  # --- Reschedule Flow ---

  def handle_reschedule(result, patient, conversation)
    entities = result[:entities] || {}
    appointments = patient.appointments.upcoming

    return if appointments.empty?

    # If new date/time provided, attempt reschedule
    if entities[:date].present? && entities[:time].present?
      appointment = appointments.first
      return unless appointment.google_event_id

      calendar = GoogleCalendarService.new
      new_start = Time.zone.parse("#{entities[:date]} #{entities[:time]}")

      calendar.reschedule_appointment(
        appointment.google_event_id,
        new_start: new_start
      )

      appointment.reload
      send_reschedule_template(patient, appointment)
    end
  rescue GoogleCalendarService::Error => e
    Rails.logger.error("[WhatsApp] Reschedule failed: #{e.message}")
  end

  # --- Cancellation Flow ---

  def handle_cancellation(result, patient, conversation)
    appointments = patient.appointments.upcoming

    return if appointments.empty?

    appointment = appointments.first
    return unless appointment.google_event_id

    calendar = GoogleCalendarService.new

    # Extract cancellation reason from entities or default
    reason_category = extract_cancellation_reason(result)

    calendar.cancel_appointment(
      appointment.google_event_id,
      reason_category: reason_category,
      reason_details: "Cancelled via WhatsApp"
    )

    appointment.reload
    send_cancellation_template(patient, appointment)
  rescue GoogleCalendarService::Error => e
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

  # --- Urgent Flow ---

  def handle_urgent(patient, conversation)
    # Flag for immediate follow-up
    send_flagged_alert(patient, "URGENT: Patient reported dental emergency via WhatsApp")
  end

  # --- Template Sending (best-effort) ---

  def send_confirmation_template(patient, appointment)
    # Send detailed booking confirmation with directions via free-form
    # message (within the 24-hour service window since the patient
    # just messaged us). Falls back to the Twilio template if the
    # free-form send fails.
    send_booking_confirmation_message(patient, appointment)
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
  def send_booking_confirmation_message(patient, appointment)
    day_name  = appointment.start_time.strftime("%A")
    date_str  = appointment.start_time.strftime("%-d %B %Y")
    time_str  = appointment.start_time.strftime("%H:%M")
    arrive_at = (appointment.start_time - 15.minutes).strftime("%H:%M")
    greeting  = time_greeting

    body = <<~MSG.strip
      #{greeting},

      Appointment has been booked for

      #{day_name}
      #{date_str}
      #{time_str}

      Please arrive at #{arrive_at} to open a new patient file.

      Looking forward to seeing you,
      Dr Chalita & team
      🌸🌿

      #{PRACTICE_DIRECTIONS}
    MSG

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

  def build_fallback_result(message:, conversation:)
    # First try urgent (always immediate)
    result = build_local_result(message: message, conversation: conversation)
    return result if result

    # When AI is unavailable, handle FAQ/pricing locally
    msg_lower = message.downcase

    if msg_lower.match?(/\b(hours?|open|closed|time|schedule)\b/)
      return {
        response: AiService::FAQ["hours"],
        intent: "faq",
        entities: {}
      }
    end

    if msg_lower.match?(/\b(price|cost|how much|consultation|cleaning)\b/)
      return {
        response: "Consultation: #{AiService::PRICING['consultation']} | Cleaning: #{AiService::PRICING['cleaning']}",
        intent: "faq",
        entities: {}
      }
    end

    {
      response: "I'm sorry, our system is a bit busy right now. Please send your preferred day and time, and our team will follow up as soon as possible.",
      intent: "book",
      entities: {}
    }
  end

  def build_local_result(message:, conversation:)
    # Only use fast path for urgent/emergency (always immediate)
    # Don't use for book/reschedule/cancel (need multi-turn with AI)
    if message.downcase.match?(/\b(pain|urgent|emergency|swollen|bleeding)\b/)
      return {
        response: "I'm sorry you're dealing with that. If this is urgent, please call the practice directly now so we can assist you as quickly as possible.",
        intent: "urgent",
        entities: {}
      }
    end

    # For other intents, let Claude handle multi-turn conversation
    nil
  end

  def build_local_result_disabled(message:, conversation:)
    # DISABLED: These patterns were causing conversation loops
    # Now delegating to AI service for proper multi-turn handling

    if message.downcase.match?(/\b(book|appointment|schedule)\b/)
      return {
        response: "I'd be happy to help you book an appointment. Please send your preferred day and time, and our team will follow up as soon as possible.",
        intent: "book",
        entities: {}
      }
    end

    if message.downcase.match?(/\b(reschedule|move|change)\b/)
      return {
        response: "I can help with a reschedule. Please send your current appointment day and the new day and time you'd prefer, and our team will follow up shortly.",
        intent: "reschedule",
        entities: {}
      }
    end

    if message.downcase.match?(/\b(cancel|cancellation)\b/)
      return {
        response: "I can help with that. If you'd like, send the appointment day and whether you'd prefer to cancel or reschedule, and our team will follow up shortly.",
        intent: "cancel",
        entities: {}
      }
    end

    if combined_text.match?(/\b(hour|hours|open|closing|close|time)\b/)
      return {
        response: AiService::FAQ["hours"],
        intent: "faq",
        entities: {}
      }
    end

    if combined_text.match?(/\b(where|location|address|directions|pretoria)\b/)
      return {
        response: AiService::FAQ["location"],
        intent: "faq",
        entities: {}
      }
    end

    if combined_text.match?(/\b(payment|medical aid|medicalaid|card|cash)\b/)
      return {
        response: AiService::FAQ["payment"],
        intent: "faq",
        entities: {}
      }
    end

    if combined_text.match?(/\b(service|services|treatment|treatments)\b/)
      return {
        response: AiService::FAQ["services"],
        intent: "faq",
        entities: {}
      }
    end

    if combined_text.match?(/\b(price|pricing|cost|quote|consultation|cleaning)\b/)
      return {
        response: "A consultation is #{AiService::PRICING['consultation']}. A cleaning is #{AiService::PRICING['cleaning']}. For other treatments, the doctor would first need to assess you at a consultation.",
        intent: "faq",
        entities: {}
      }
    end

    nil
  end

  def persist_exchange(conversation, user_message, assistant_message)
    conversation.add_messages([
      { role: "user", content: user_message },
      { role: "assistant", content: assistant_message }
    ])
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
