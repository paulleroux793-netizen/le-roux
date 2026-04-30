class VoiceService
  VOICE            = "Polly.Joanna"
  GATHER_TIMEOUT   = "5"    # seconds of silence before giving up on current utterance
  CONFIDENCE_FLOOR = 0.3    # ignore speech below this Twilio confidence score

  GREETING = <<~TEXT.strip
    Hello, you've reached Dr Chalita le Roux's dental practice. I'm the AI assistant and I can help you book, \
reschedule, or cancel an appointment, or answer any questions about our practice. How can I help you today?
  TEXT

  NO_SPEECH_REPLY = <<~TEXT.strip
    I'm sorry, I didn't catch that. Please try speaking again, or send us a WhatsApp message and we'll get back \
to you shortly.
  TEXT

  GOODBYE_REPLY = <<~TEXT.strip
    Thank you for calling Dr Chalita le Roux's practice. We look forward to seeing you. Goodbye!
  TEXT

  GOODBYE_PATTERNS = /\b(goodbye|bye|thank you|thanks|that'?s all|that is all|nothing else|no thanks|no thank you)\b/i

  # ── Inbound call flow ────────────────────────────────────────────────

  # Called when a patient first dials in.
  # Creates the call log and conversation, then returns greeting TwiML.
  def handle_incoming(call_sid:, caller:)
    patient      = find_or_create_patient(caller)
    conversation = create_voice_conversation(patient)
    create_call_log(call_sid: call_sid, caller: caller, patient: patient)

    gather_twiml(GREETING, gather_url)
  end

  # Called after each speech turn from the patient.
  # Runs the message through AI and returns the next TwiML gather loop.
  def handle_gather(call_sid:, speech_result:, confidence:)
    call_log     = CallLog.find_by(twilio_call_sid: call_sid)
    patient      = call_log&.patient
    conversation = find_active_voice_conversation(patient)

    # If Twilio returned nothing intelligible, prompt again
    if speech_result.blank? || confidence < CONFIDENCE_FLOOR
      return gather_twiml(NO_SPEECH_REPLY, gather_url)
    end

    result = ai_service.process_message(
      message:      speech_result,
      conversation: conversation,
      patient:      patient,
      channel:      :voice
    )

    update_call_log(call_log, result)

    return farewell_twiml(GOODBYE_REPLY) if goodbye_detected?(speech_result)

    gather_twiml(result[:response], gather_url)
  rescue AiService::Error => e
    Rails.logger.warn("[Voice] AI unavailable: #{e.message}")
    gather_twiml(
      "I'm sorry, I'm having a little trouble right now. " \
      "Please try again or send us a WhatsApp message and we'll be in touch. Goodbye.",
      gather_url
    )
  end

  # Called when the call lifecycle changes (completed, busy, no-answer, failed).
  def handle_status(call_sid:, call_status:, duration:)
    call_log = CallLog.find_by(twilio_call_sid: call_sid)
    return unless call_log

    call_log.update!(status: call_status, duration: duration)

    if %w[completed busy no-answer failed].include?(call_status)
      find_active_voice_conversation(call_log.patient)&.close!
    end
  end

  # ── Outbound confirmation flow ───────────────────────────────────────

  # Returns TwiML for an outbound confirmation call placed by ConfirmationService.
  # Reads appointment details aloud and gathers a single DTMF keypress.
  def confirmation_twiml(appointment)
    unless appointment
      return farewell_twiml("Thank you for answering. Please disregard this call. Goodbye.")
    end

    patient       = appointment.patient
    date          = appointment.start_time.strftime("%A, %B %d")
    time          = appointment.start_time.strftime("%I:%M %p")
    gather_action = "#{base_url}/webhooks/voice/confirmation_gather?appointment_id=#{appointment.id}"

    Twilio::TwiML::VoiceResponse.new do |r|
      r.gather(input: "dtmf", action: gather_action, num_digits: "1", timeout: "10") do |g|
        g.say(
          message: "Hello #{patient.first_name}, this is a reminder from Dr Chalita le Roux's dental practice. " \
                   "You have an appointment on #{date} at #{time}. " \
                   "Press 1 to confirm, press 2 to reschedule, or press 3 to cancel.",
          voice: VOICE
        )
      end
      r.say(
        message: "We didn't receive a response. Please call us or send a WhatsApp message to confirm your appointment. Goodbye.",
        voice: VOICE
      )
      r.hangup
    end.to_xml
  end

  # Handles the patient's DTMF keypress from the outbound confirmation call.
  # Updates the appointment status and the confirmation log.
  def handle_confirmation_gather(call_sid:, digits:, appointment_id:)
    appointment = Appointment.find_by(id: appointment_id)
    return farewell_twiml("Thank you. Goodbye.") unless appointment

    log = appointment.confirmation_logs.order(created_at: :desc).first

    case digits.to_s.strip
    when "1"
      appointment.confirmed!
      log&.update!(outcome: "confirmed", flagged: false)
      farewell_twiml("Thank you, your appointment is confirmed. We look forward to seeing you. Goodbye!")

    when "2"
      log&.update!(outcome: "rescheduled", flagged: true)
      farewell_twiml(
        "Thank you. A member of our team will be in touch shortly to arrange a new time for you. Goodbye!"
      )

    when "3"
      appointment.cancelled!
      log&.update!(outcome: "cancelled", flagged: true)
      farewell_twiml(
        "Your appointment has been cancelled. We hope to see you again soon. Goodbye!"
      )

    else
      log&.update!(outcome: "unclear", flagged: true)
      farewell_twiml(
        "We didn't understand your response. Please call us or send a WhatsApp message. Goodbye!"
      )
    end
  end

  private

  # ── TwiML helpers ────────────────────────────────────────────────────

  # Speaks `message`, then listens for the next speech turn.
  # If no speech is detected within GATHER_TIMEOUT, hangs up with a polite farewell.
  def gather_twiml(message, action)
    Twilio::TwiML::VoiceResponse.new do |r|
      r.gather(input: "speech", action: action, timeout: GATHER_TIMEOUT, speech_timeout: "auto") do |g|
        g.say(message: message, voice: VOICE)
      end
      r.say(
        message: "I didn't hear anything. Please call us back or send a WhatsApp message. Goodbye.",
        voice: VOICE
      )
      r.hangup
    end.to_xml
  end

  def farewell_twiml(message)
    Twilio::TwiML::VoiceResponse.new do |r|
      r.say(message: message, voice: VOICE)
      r.hangup
    end.to_xml
  end

  # ── URL helpers ──────────────────────────────────────────────────────

  def gather_url
    "#{base_url}/webhooks/voice/gather"
  end

  def base_url
    ENV.fetch("APP_BASE_URL", "http://localhost:3000")
  end

  # ── Patient / conversation / call log helpers ────────────────────────

  def find_or_create_patient(phone)
    normalized = normalize_phone(phone)
    Patient.find_or_create_by!(phone: normalized) do |p|
      p.first_name = "Phone"
      p.last_name  = "Caller"
    end
  rescue ActiveRecord::RecordInvalid
    Patient.find_by!(phone: normalize_phone(phone))
  end

  def create_voice_conversation(patient)
    patient.conversations.create!(
      channel:    "voice",
      status:     "active",
      messages:   [],
      started_at: Time.current
    )
  end

  def find_active_voice_conversation(patient)
    return nil unless patient

    patient.conversations
      .where(channel: "voice", status: "active")
      .order(updated_at: :desc)
      .first
  end

  def create_call_log(call_sid:, caller:, patient:)
    CallLog.find_or_create_by!(twilio_call_sid: call_sid) do |log|
      log.caller_number = caller
      log.patient       = patient
      log.status        = "in-progress"
    end
  end

  def update_call_log(call_log, result)
    return unless call_log

    call_log.update!(
      intent:      result[:intent],
      ai_response: result[:response]
    )
  end

  def normalize_phone(phone)
    phone.gsub(/\s+/, "").then { |p| p.start_with?("+") ? p : "+#{p}" }
  end

  def goodbye_detected?(speech)
    speech.match?(GOODBYE_PATTERNS)
  end

  def ai_service
    @ai ||= AiService.new
  end
end
