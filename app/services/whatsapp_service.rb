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

  def handle_booking(result, patient, conversation)
    entities = result[:entities] || {}
    date = entities[:date]
    time = entities[:time]

    # No concrete date/time yet — the AI is still gathering preferences
    # over multiple turns. Nothing to verify; let the AI text stand.
    return unless date.present? && time.present?

    appointment = attempt_booking(patient, date, time, entities[:treatment])

    if appointment.nil?
      # Booking was attempted (date+time present) but didn't persist.
      # Replace the AI's optimistic confirmation with an honest reply.
      result[:response] = BOOKING_FAILED_FALLBACK
    end
  end

  # Returns the persisted Appointment on success, or nil on any
  # failure (slot not available, Google API error, missing creds).
  # Never raises — the caller relies on the nil sentinel.
  def attempt_booking(patient, date, time, treatment)
    calendar = GoogleCalendarService.new
    start_time = Time.zone.parse("#{date} #{time}")
    reason = treatment&.capitalize || "Consultation"

    slots = calendar.available_slots(Date.parse(date))
    matching_slot = slots.find { |s| s[:start_time] == start_time }

    return nil unless matching_slot

    appointment = calendar.book_appointment(
      patient: patient,
      start_time: start_time,
      reason: reason
    )
    send_confirmation_template(patient, appointment)
    appointment
  rescue StandardError => e
    Rails.logger.error("[WhatsApp] Booking failed: #{e.class}: #{e.message}")
    nil
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
    template_service&.send_confirmation(patient, appointment)
  rescue WhatsappTemplateService::Error => e
    Rails.logger.warn("[WhatsApp] Template send failed: #{e.message}")
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
