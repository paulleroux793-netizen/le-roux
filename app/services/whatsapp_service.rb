class WhatsappService
  class Error < StandardError; end

  def initialize
    @ai = AiService.new
    @templates = WhatsappTemplateService.new
  rescue StandardError
    # Template service may fail if Twilio creds aren't set (dev/test)
    @templates = nil
  end

  # Main entry point: handle an incoming WhatsApp message.
  # Returns { response:, intent:, entities: }
  def handle_incoming(from:, message:, twilio_params: {})
    patient = find_or_create_patient(from)
    conversation = find_or_create_conversation(patient)

    # Process through AI brain
    result = @ai.process_message(
      message: message,
      conversation: conversation,
      patient: patient
    )

    # Route based on detected intent
    handle_intent(result, patient, conversation)

    result
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

  def handle_booking(result, patient, conversation)
    entities = result[:entities] || {}
    date = entities[:date]
    time = entities[:time]

    # If we have both date and time, try to book
    if date.present? && time.present?
      attempt_booking(patient, date, time, entities[:treatment])
    end
    # Otherwise, the AI response already asks for preferences
  end

  def attempt_booking(patient, date, time, treatment)
    calendar = GoogleCalendarService.new
    start_time = Time.zone.parse("#{date} #{time}")
    reason = treatment&.capitalize || "Consultation"

    # Check availability
    slots = calendar.available_slots(Date.parse(date))
    matching_slot = slots.find { |s| s[:start_time] == start_time }

    if matching_slot
      appointment = calendar.book_appointment(
        patient: patient,
        start_time: start_time,
        reason: reason
      )
      send_confirmation_template(patient, appointment)
    end
  rescue GoogleCalendarService::Error => e
    Rails.logger.error("[WhatsApp] Booking failed: #{e.message}")
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
    @templates&.send_confirmation(patient, appointment)
  rescue WhatsappTemplateService::Error => e
    Rails.logger.warn("[WhatsApp] Template send failed: #{e.message}")
  end

  def send_reschedule_template(patient, appointment)
    @templates&.send_reschedule(patient, appointment)
  rescue WhatsappTemplateService::Error => e
    Rails.logger.warn("[WhatsApp] Template send failed: #{e.message}")
  end

  def send_cancellation_template(patient, appointment)
    @templates&.send_cancellation(patient, appointment)
  rescue WhatsappTemplateService::Error => e
    Rails.logger.warn("[WhatsApp] Template send failed: #{e.message}")
  end

  def send_flagged_alert(patient, reason)
    @templates&.send_flagged_alert(patient, reason)
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
end
