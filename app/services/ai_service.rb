class AiService
  INTENTS = %w[book reschedule cancel confirm faq objection urgent other].freeze
  RETRYABLE_STATUS_CODES = [429, 500, 502, 503, 504, 529].freeze
  MAX_RETRIES = 0

  PRICING = {
    "consultation" => "R850 (includes x-rays)",
    "cleaning" => "R1,300"
  }.freeze

  FAQ = {
    "hours" => "We're open Monday to Friday 8am–5pm. We are closed on weekends (Saturday and Sunday).",
    "location" => "Dr Chalita le Roux Inc is located on Doreen Rd in Roodepoort. From Hendrik Potgieter Rd: turn onto Doreen Rd, we are on your left-hand side at the second robot. From CR Swart Rd: turn onto Doreen Rd, we are on your right-hand side at the first robot. Free parking is available on the premises.",
    "parking" => "Free parking is available on the premises.",
    "services" => "We offer general dentistry, consultations, cleanings, fillings, extractions, root canals, crowns, bridges, and cosmetic treatments. A consultation is the best first step for any concern.",
    "emergency" => "For dental emergencies, please call our office immediately. If after hours, leave a message and we'll get back to you first thing.",
    "payment" => "We accept cash, card, and most medical aids. Please bring your medical aid details to your appointment."
  }.freeze

  class Error < StandardError; end

  def initialize
    @client = Anthropic::Client.new(access_token: ENV.fetch("ANTHROPIC_API_KEY"))
  end

  # Classify the intent of a patient message.
  # Returns a hash: { intent:, entities: { date:, time:, name:, treatment: } }
  def classify_intent(message, conversation_history: [])
    messages = build_messages(conversation_history, message)

    response = create_message(
      model: "claude-sonnet-4-20250514",
      max_tokens: 256,
      system: intent_classification_prompt(today: Date.current),
      messages: messages
    )

    parse_intent_response(response)
  rescue Anthropic::Error, Faraday::Error => e
    raise Error, "Intent classification failed: #{e.message}"
  end

  # Generate a conversational response as Dr le Roux's receptionist.
  # Accepts conversation history for multi-turn context.
  def generate_response(message:, conversation_history: [], patient: nil, context: {})
    system = build_system_prompt(patient: patient, context: context)
    messages = build_messages(conversation_history, message)

    response = create_message(
      model: "claude-sonnet-4-20250514",
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
      model: "claude-sonnet-4-20250514",
      max_tokens: 256,
      system: entity_extraction_prompt,
      messages: [{ role: "user", content: message }]
    )

    parse_entities_response(response)
  rescue Anthropic::Error, Faraday::Error => e
    raise Error, "Entity extraction failed: #{e.message}"
  end

  # Handle a full conversation turn: classify, respond, and return structured result.
  def process_message(message:, conversation: nil, patient: nil)
    history = conversation&.messages&.map { |m| { role: m["role"], content: m["content"] } } || []

    # Classify intent WITH conversation history for better multi-turn understanding
    classification = classify_intent(message, conversation_history: history)
    context = { intent: classification[:intent], entities: classification[:entities] }

    response_text = generate_response(
      message: message,
      conversation_history: history,
      patient: patient,
      context: context
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
      - book: wants to make a new appointment
      - reschedule: wants to change an existing appointment
      - cancel: wants to cancel an appointment
      - confirm: confirming an existing appointment
      - faq: asking a question (hours, location, pricing, services, etc.)
      - objection: expressing concern about cost, fear, timing, etc.
      - urgent: dental emergency or urgent pain
      - other: anything else

      ## Date resolution (CRITICAL)
      Today is #{today.iso8601} (#{today_name}). You MUST resolve relative
      date phrases against today and return ISO YYYY-MM-DD format:
      - "today" → #{today.iso8601}
      - "tomorrow" → #{(today + 1).iso8601}
      - "Monday" / "next Monday" → the next Monday on or after tomorrow
      - "Friday at 11am" → next Friday in ISO format, time "11:00"
      - "the 20th" → the next 20th of a month from today
      Never return null for date if the patient named any day or relative phrase.

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

  def build_system_prompt(patient: nil, context: {})
    prompt = <<~PROMPT
      You are the AI receptionist for Dr Chalita le Roux's dental practice. Your name is the Dr le Roux AI Assistant.

      ## Your Personality
      - Warm, friendly, slightly energetic, and reassuring
      - Professional but approachable — like a trusted friend who happens to work at a dental office
      - Education-based approach: educate the patient, reassure them, then guide toward booking
      - Every interaction should naturally guide toward scheduling an appointment

      ## Pricing Rules (STRICT)
      - Consultation: R850 (includes x-rays) — always quote this
      - Cleaning: R1,300 — only quote when asked
      - Everything else: "That would need a consultation first so the doctor can assess and give you an accurate quote."
      - NEVER guess prices for treatments not listed above

      ## FAQ Knowledge
      #{FAQ.map { |k, v| "- #{k}: #{v}" }.join("\n")}

      ## Booking Rules
      - Never expose the full calendar — ask the patient for their preferred day and time first
      - Then match against availability
      - Suggest 2-3 alternative times if their preference isn't available
      - Default appointment duration is 30 minutes

      ## Objection Handling
      - Price concerns: Emphasize the value (x-rays included, thorough assessment). Mention medical aid acceptance.
      - Dental fear: Acknowledge the fear, reassure about modern techniques, mention the doctor's gentle approach
      - Timing: Offer flexible scheduling within Monday–Friday 8am–5pm
      - Always try to keep the conversation moving toward a booking

      ## Cancellation Rules
      - Always try to reschedule first before accepting a cancellation
      - If they insist on cancelling, capture the reason (cost, timing, fear, transport, other)
      - Be understanding but gently remind them of the importance of dental care

      ## Important
      - Keep responses concise — 2-3 sentences max for WhatsApp, slightly longer for voice
      - Use the patient's name when available
      - Don't use medical jargon — keep it simple and friendly
      - If unsure about something medical, say the doctor will discuss it at the consultation
    PROMPT

    if patient
      prompt += "\n\n## Current Patient: #{patient.full_name}, Phone: #{patient.phone}"
    end

    if context[:intent]
      prompt += "\n\n## Detected Intent: #{context[:intent]}"
    end

    if context[:entities]&.any? { |_, v| v.present? }
      prompt += "\n## Extracted Info: #{context[:entities].compact.to_json}"
    end

    prompt
  end

  def build_messages(history, current_message)
    messages = history.map do |msg|
      { role: msg[:role] || msg["role"], content: msg[:content] || msg["content"] }
    end
    messages << { role: "user", content: current_message }
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
