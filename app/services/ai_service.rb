class AiService
  INTENTS = %w[book reschedule cancel confirm faq objection urgent other].freeze
  RETRYABLE_STATUS_CODES = [ 429, 500, 502, 503, 504, 529 ].freeze
  MAX_RETRIES = 0

  PRICING = {
    "consultation" => "approximately R850 (may include X-rays, excludes 2D/3D scans)",
    "check_up" => "approximately R1,600",
    "cleaning" => "approximately R1,500"
  }.freeze

  PRACTICE_ADDRESS = "Unit 2, Amorosa Office Park, Corner of Doreen Road & Lawrence Rd, Amorosa, Roodepoort, Johannesburg, 2040".freeze
  PRACTICE_MAP_LINK = "https://maps.app.goo.gl/3iHKg7AMa8qRcfLf6".freeze
  PRACTICE_DIRECTIONS = "From Hendrik Potgieter Rd: Turn onto Doreen Rd, we are on your left-hand side at the second robot. From CR Swart Rd: Turn onto Doreen Rd, we are on your right-hand side at the first robot.".freeze

  FAQ = {
    "hours" => nil, # Dynamic — use AiService.dynamic_hours instead
    "location" => "Our practice is located at: #{PRACTICE_ADDRESS}\nGoogle Maps: #{PRACTICE_MAP_LINK}\nDirections: #{PRACTICE_DIRECTIONS}",
    "parking" => "Free parking is available on the premises.",
    "services" => "We offer general dentistry, check-ups, cleanings, fillings, extractions, root canals, crowns, bridges, and cosmetic treatments. An examination is the best first step for any concern.",
    "emergency" => "For dental emergencies, please contact Dr Chalita directly at 071 884 3204. If after hours, call that number and we'll assist you as quickly as possible.",
    "payment" => "We do not claim directly from medical aid. All patients pay at the practice, and we then provide a statement so you can claim back from your medical aid. We have card facilities at the practice and also accept cash."
  }.freeze

  class Error < StandardError; end

  # Dynamic hours text from DoctorSchedule DB records.
  # Used as local fallback when AI is unavailable.
  def self.dynamic_hours
    schedules = DoctorSchedule.order(:day_of_week).to_a
    active = schedules.select(&:active?)

    if active.any?
      sample = active.first
      start_h = sample.start_time.strftime("%-I%P")
      end_h = sample.end_time.strftime("%-I%P")
      days = active.map(&:day_name).map(&:capitalize)
      closed = schedules.reject(&:active?).map(&:day_name).map(&:capitalize)
      "We're open #{days.first} to #{days.last} #{start_h}–#{end_h}. We are closed on #{closed.join(' and ')}."
    else
      "We're open Monday to Friday. We are closed on weekends (Saturday and Sunday)."
    end
  end

  def initialize
    @client = Anthropic::Client.new(access_token: ENV.fetch("ANTHROPIC_API_KEY"))
  end

  # Classify the intent of a patient message.
  # Returns a hash: { intent:, entities: { date:, time:, name:, treatment: } }
  def classify_intent(message, conversation_history: [])
    messages = build_messages(conversation_history, message)

    response = create_message(
      model: "claude-sonnet-4-6",
      max_tokens: 256,
      system: intent_classification_prompt(today: Date.current),
      messages: messages
    )

    parse_intent_response(response)
  rescue Anthropic::Error, Faraday::Error => e
    raise Error, "Intent classification failed: #{e.message}"
  end

  # Generate a conversational response as Dr le Roux's receptionist.
  # Accepts conversation history and optional media attachments (PDFs/images).
  def generate_response(message:, conversation_history: [], patient: nil, context: {}, media_attachments: [])
    system = build_system_prompt(patient: patient, context: context)
    messages = build_messages(conversation_history, message, media_attachments: media_attachments)

    response = create_message(
      model: "claude-sonnet-4-6",
      max_tokens: 1024,
      system: system,
      messages: messages
    )

    extract_text(response)
  rescue Anthropic::Error, Faraday::Error => e
    raise Error, "Response generation failed: #{e.message}"
  end

  # Extract structured entities from a message (date, time, name, treatment).
  def extract_entities(message)
    response = create_message(
      model: "claude-sonnet-4-6",
      max_tokens: 256,
      system: entity_extraction_prompt,
      messages: [ { role: "user", content: message } ]
    )

    parse_entities_response(response)
  rescue Anthropic::Error, Faraday::Error => e
    raise Error, "Entity extraction failed: #{e.message}"
  end

  # Handle a full conversation turn: classify, respond, and return structured result.
  def process_message(message:, conversation: nil, patient: nil, media_attachments: [])
    raw_history = (conversation&.messages || []).last(20)
    sanitized = []
    raw_history.each do |m|
        r = (m["role"] || m[:role]).to_s
      c = (m["content"] || m[:content]).to_s
      next unless %w[user assistant].include?(r)
      next if c.strip.empty?
      next if sanitized.last && sanitized.last[:role] == r
      sanitized << { role: r, content: c }
    end
    sanitized.shift while sanitized.any? && sanitized.first[:role] != "user"
      sanitized.pop if sanitized.last && sanitized.last[:role] == "user"
      history = sanitized

    # Classify intent WITH conversation history for better multi-turn understanding
    classification = classify_intent(message, conversation_history: history)
    language = conversation&.language || "en"
    context = { intent: classification[:intent], entities: classification[:entities], language: language }

    # Inject real appointment availability so the bot can offer genuine alternatives
    inject_availability_context!(context, classification, patient)

    response_text = generate_response(
      message: message,
      conversation_history: history,
      patient: patient,
      context: context,
      media_attachments: media_attachments
    )

    # Store messages in conversation if provided
    if conversation
      conversation.add_messages([
        { role: "user", content: message },
        { role: "assistant", content: response_text }
      ])
    end

    {
      response: response_text,
      intent: classification[:intent],
      entities: classification[:entities]
    }
  end

  private

  def create_message(**parameters)
    attempts = 0

    begin
      attempts += 1
      @client.messages(parameters: parameters)
    rescue Faraday::Error => e
      raise unless retryable_error?(e) && attempts <= MAX_RETRIES

      sleep(0.25 * attempts)
      retry
    end
  end

  def retryable_error?(error)
    RETRYABLE_STATUS_CODES.include?(error.response_status || error.response&.dig(:status))
  end

  def intent_classification_prompt(today: Date.current)
    today_name = today.strftime("%A")
    <<~PROMPT
      You are an intent classifier for a dental receptionist AI. Classify the patient's message into exactly one intent and extract any entities.

      Intents: #{INTENTS.join(', ')}
      - book: wants to make a new appointment (includes check-up, cleaning, cosmetic consultation, fillings, any dental treatment, or general booking request)
      - reschedule: wants to change an existing appointment
      - cancel: wants to cancel an appointment
      - confirm: confirming an existing appointment (e.g., "CONFIRM", "yes I'll be there")
      - faq: asking a question (hours, location, pricing, services, payment, medical aid, directions)
      - objection: expressing concern about cost, fear, timing, or pushing back on pricing
      - urgent: dental emergency, severe pain, swelling, bleeding, trauma, broken tooth
      - other: anything else, including greetings, human help requests, unclear messages

      ## Enquiry-to-intent mapping
      These patient enquiries all map to "book":
      - pain or dental emergency → "urgent" (NOT book)
      - general dental check-up → "book" with treatment "check-up"
      - cosmetic consultation → "book" with treatment "cosmetic consultation"
      - teeth cleaning → "book" with treatment "cleaning"
      - fillings or restorative work → "book" with treatment "filling"
      - other dental treatment → "book"
      - booking request → "book"
      - payment or medical aid question → "faq"
      - location or directions → "faq"
      - human help requested → "other"

      ## Date resolution (CRITICAL)
      Today is #{today.iso8601} (#{today_name}). You MUST resolve relative
      date phrases against today and return ISO YYYY-MM-DD format:
      - "today" → #{today.iso8601}
      - "tomorrow" → #{(today + 1).iso8601}
      - "Monday" / "next Monday" → the next Monday on or after tomorrow
      - "Friday at 11am" → next Friday in ISO format, time "11:00"
      - "the 20th" → the next 20th of a month from today
      IMPORTANT: The practice is CLOSED on Saturday and Sunday. If the patient requests a weekend date, still extract it but note the practice is only open Monday–Friday.
      Never return null for date if the patient named any day or relative phrase.

      ## Multi-turn reschedule context (CRITICAL)
      If the conversation history shows a reschedule is in progress — e.g., the patient tapped "RESCHEDULE APPOINTMENT" or the bot asked "please send your preferred date and time" — classify follow-up messages as "reschedule" even without the word "reschedule". Examples:
      - "Same time at 2pm" → {"intent": "reschedule", "entities": {"time": "14:00"}}
      - "How about Monday?" → {"intent": "reschedule", "entities": {"date": "YYYY-MM-DD"}}
      - "Next available" / "earliest available" / "next earliest" → {"intent": "reschedule", "entities": {}}
      - "The next earliest available appointment" → {"intent": "reschedule", "entities": {}}
      - "Same time, next available slot" → {"intent": "reschedule", "entities": {}}
      NEVER classify these as "faq" or "book" when a reschedule conversation is active.

      Respond ONLY with valid JSON:
      {"intent": "book", "entities": {"date": "2026-04-17", "time": "11:00", "name": "John", "treatment": "cleaning"}}

      Use null only for entities the patient genuinely did not mention. Dates ISO YYYY-MM-DD, times HH:MM 24-hour.
    PROMPT
  end

  def entity_extraction_prompt
    <<~PROMPT
      Extract structured entities from the patient's message for a dental appointment system.

      Respond ONLY with valid JSON:
      {"date": "2026-04-15", "time": "10:00", "name": "John Smith", "treatment": "consultation", "phone": "+27612345678"}

      Use null for any entity you cannot determine. Dates in ISO format, times in HH:MM.
    PROMPT
  end


  # Delegates to PromptBuilder, which assembles the full system prompt
  # and injects dynamically fetched Afrikaans examples when applicable.
  def build_system_prompt(patient: nil, context: {})
    PromptBuilder.new(patient: patient, context: context).build
  end

  # Mutates `context` in place with real availability data so PromptBuilder
  # can surface genuine slots and the bot stops claiming it has no calendar access.
  def inject_availability_context!(context, classification, patient)
    return unless %w[book reschedule].include?(classification[:intent])

    requested_date = begin
      raw = classification.dig(:entities, :date)
      Date.parse(raw) if raw.present?
    rescue ArgumentError
      nil
    end

    from_date = [ requested_date, Date.current ].compact.max
    slots = AvailabilityService.new.next_available_slots(from_date: from_date, limit: 5)
    context[:available_slots] = slots unless slots.empty?

    if patient
      upcoming = patient.appointments.upcoming.limit(3).map do |a|
        "#{a.start_time.strftime('%A, %-d %B at %H:%M')} (#{a.status.humanize} – #{a.reason})"
      end
      context[:patient_appointments] = upcoming unless upcoming.empty?
    end
  rescue StandardError => e
    Rails.logger.warn("[AiService] inject_availability_context! failed: #{e.message}")
  end

  # Check if a given time falls within working hours.
  # Kept here for use by other callers (e.g. fallback response builder).
  def within_working_hours?(time)
    schedule = DoctorSchedule.for_day(time.wday)
    return false unless schedule

    schedule.working?(time)
  rescue StandardError
    time.wday.between?(1, 5) && time.hour >= 8 && time.hour < 17
  end

  def build_messages(history, current_message, media_attachments: [])
    messages = history.map do |msg|
      { role: msg[:role] || msg["role"], content: msg[:content] || msg["content"] }
    end

    # When media is present, the current message content becomes a block array
    # so Claude can process documents/images alongside the text.
    user_content = if media_attachments.present?
      document_blocks = media_attachments.map do |attachment|
        {
          type: "document",
          source: {
            type: "base64",
            media_type: attachment[:content_type],
            data: attachment[:data]
          }
        }
      end
      document_blocks + [ { type: "text", text: current_message } ]
    else
      current_message
    end

    messages << { role: "user", content: user_content }
    messages
  end

  def parse_intent_response(response)
    text = extract_text(response)
    json = JSON.parse(text)
    {
      intent: json["intent"],
      entities: {
        date: json.dig("entities", "date"),
        time: json.dig("entities", "time"),
        name: json.dig("entities", "name"),
        treatment: json.dig("entities", "treatment")
      }
    }
  rescue JSON::ParserError
    { intent: "other", entities: {} }
  end

  def parse_entities_response(response)
    text = extract_text(response)
    JSON.parse(text).symbolize_keys
  rescue JSON::ParserError
    {}
  end

  def extract_text(response)
    response.dig("content", 0, "text")
  end
end
