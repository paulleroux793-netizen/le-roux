class AiService
  INTENTS = %w[book reschedule cancel confirm faq objection urgent other].freeze
  RETRYABLE_STATUS_CODES = [ 429, 500, 502, 503, 504, 529 ].freeze
  MAX_RETRIES = 0

  # Voice patients hear ~5-8s of dead air per turn on Sonnet 4.6 (two
  # sequential Claude calls per turn × 3-5s each). Haiku 4.5 cuts each
  # call to ~500ms-1s with no measurable quality drop on routine booking
  # flows, taking inter-turn latency down to ~1-2s. WhatsApp keeps Sonnet
  # because patients can wait and quality matters more than speed there.
  MODELS_PER_CHANNEL = {
    voice:    "claude-haiku-4-5",
    whatsapp: "claude-sonnet-4-6"
  }.freeze
  DEFAULT_MODEL = "claude-sonnet-4-6".freeze

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
    "emergency" => "For dental emergencies, please share your name, contact number and a short description of the issue. We're open *Monday to Friday, 8am–5pm* and we don't have dentists on duty outside those hours — we always prioritise emergencies and will book you in at the very first available slot the moment we reopen.",
    "payment" => "We do not claim directly from medical aid. All patients pay at the practice, and we then provide a statement so you can claim back from your medical aid. We have card facilities at the practice and also accept cash.",

    # ── Reception-derived FAQ entries (from Cube ACR call corpus, ──
    # Apr 2026 analysis). Reception's verbatim answers to the
    # questions patients actually ask most often. Hard-coding these
    # rather than letting the AI improvise gives consistency with
    # how a human reception team would answer.
    "walk_ins" => "We don't accept walk-ins, but I can usually offer a same-day or next-day appointment. " \
                  "What treatment do you need? I'll check what's available.",

    "consultation_cost" => "A consultation is approximately R850 (which may include x-rays, but " \
                           "excludes 2D/3D scans). Final cost depends on what the dentist recommends.",

    "filling_cost" => "Filling costs depend on the size and the type of restoration. " \
                      "After Dr Chalita has examined you and taken x-rays, she'll give you " \
                      "an exact quote before any work starts.",

    "extraction_cost" => "A standard extraction is approximately R1,900, but the final cost depends on " \
                         "the x-rays and the type of extraction needed. The dentist will give you a final " \
                         "quote after the examination. *Please note* — for surgical extractions (where the " \
                         "tooth is impacted or below the gum), we refer you to an oral surgeon, as we don't " \
                         "perform surgical extractions in-house.",

    "surgical_extraction" => "We don't perform surgical extractions in-house. If your doctor has referred you " \
                             "for a surgical extraction (where the tooth is impacted or has to be cut out), " \
                             "you'll need to see an oral surgeon. The doctor who referred you should be able " \
                             "to refer you to a surgeon directly.",

    "sedation_kids" => "Yes — for young children's first dental visit we offer sedation to make the experience " \
                       "comfortable. We typically book pediatric sedation appointments at specific times. " \
                       "How old is the child? I'll check Dr Chalita's earliest available pediatric slot.",

    "aftercare_eating" => "Yes, you can eat as normal — the cement is light-cured so it sets immediately. " \
                          "Just be careful not to bite your cheek or lip while you're still numb from the " \
                          "anaesthetic. If you have any pain or sensitivity that doesn't settle within a few " \
                          "days, please call us so we can check.",

    "family_booking" => "Of course! How many family members would you like to book, and what does each one " \
                        "need? Please share their full names so I can set up each appointment."
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
  # `channel` selects the model — :voice uses Haiku for ~3x lower latency.
  def classify_intent(message, conversation_history: [], channel: :whatsapp)
    messages = build_messages(conversation_history, message)

    response = create_message(
      model: model_for(channel),
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
  # `channel` selects the prompt format (defaults to :whatsapp for backwards
  # compatibility — voice callers pass :voice).
  def generate_response(message:, conversation_history: [], patient: nil, context: {}, channel: :whatsapp, media_attachments: [])
    system = build_system_prompt(patient: patient, context: context, channel: channel)
    messages = build_messages(conversation_history, message, media_attachments: media_attachments)

    response = create_message(
      model: model_for(channel),
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
  # `channel` selects the prompt format (:whatsapp or :voice). Defaults to
  # :whatsapp so existing WhatsApp callers don't need to change.
  def process_message(message:, conversation: nil, patient: nil, channel: :whatsapp, media_attachments: [])
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

    # Classify intent WITH conversation history for better multi-turn understanding.
    # Channel is forwarded so :voice picks Haiku 4.5 (lower latency).
    classification = classify_intent(message, conversation_history: history, channel: channel)
    language = conversation&.language || "en"
    context = { intent: classification[:intent], entities: classification[:entities], language: language }

    # Inject real appointment availability so the bot can offer genuine alternatives
    inject_availability_context!(context, classification, patient)

    response_text = generate_response(
      message: message,
      conversation_history: history,
      patient: patient,
      context: context,
      channel: channel,
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

    response = begin
      attempts += 1
      @client.messages(parameters: parameters)
    rescue Faraday::Error => e
      raise Error, "Anthropic API error: #{e.message}" if attempts >= 3 || !retryable_error?(e)

      sleep(0.25 * attempts)
      retry
    end

    log_anthropic_usage(parameters, response)
    response
  end

  ANTHROPIC_RATES = {
    "claude-sonnet-4-6"  => { input: 3.0,  output: 15.0 },
    "claude-haiku-4-5"   => { input: 1.0,  output: 5.0  },
    "claude-opus-4-6"    => { input: 15.0, output: 75.0 }
  }.freeze

  def log_anthropic_usage(parameters, response)
    usage = response.is_a?(Hash) ? (response["usage"] || response[:usage] || {}) : {}
    input_tokens  = usage["input_tokens"].to_i
    output_tokens = usage["output_tokens"].to_i
    model = (parameters[:model] || parameters["model"] || "claude-sonnet-4-6").to_s
    rates = ANTHROPIC_RATES[model] || ANTHROPIC_RATES["claude-sonnet-4-6"]
    cost_usd = ((input_tokens * rates[:input]) + (output_tokens * rates[:output])) / 1_000_000.0

    Rails.logger.info(
      "[AiCost] model=#{model} input_tokens=#{input_tokens} " \
      "output_tokens=#{output_tokens} est_usd=#{format('%.6f', cost_usd)}"
    )

    today = Date.current.to_s
    Rails.cache.increment("ai_cost:#{today}:calls", 1, expires_in: 40.days) rescue nil
    Rails.cache.increment("ai_cost:#{today}:input_tokens",  input_tokens,  expires_in: 40.days) rescue nil
    Rails.cache.increment("ai_cost:#{today}:output_tokens", output_tokens, expires_in: 40.days) rescue nil
    Rails.cache.increment("ai_cost:#{today}:cost_micros",   (cost_usd * 1_000_000).round, expires_in: 40.days) rescue nil
  rescue StandardError => e
    Rails.logger.warn("[AiCost] usage logging failed: #{e.class}: #{e.message}")
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

      ## Booking-intent rule (CRITICAL, overrides ambiguity)
      If the message contains BOTH a specific date AND a specific time, and the patient is asking about an appointment slot, the intent is "book" (or "reschedule" if a reschedule flow is active). NEVER return "other" or "faq" in that case. Always extract date + time into entities.

      ## Whitening rule
      Any mention of teeth whitening, Biolase, bleiking, tandebleiking, or laser whitening is a BOOK intent with treatment="whitening". Duration is 90 minutes (handled downstream).

      ## Few-shot examples
      Input: "Book me a cleaning Monday 4 May 2026 at 10:00"
      Output: {"intent": "book", "entities": {"date": "2026-05-04", "time": "10:00", "treatment": "cleaning"}}

      Input: "I need a check-up Thursday 15 May 09:30 please"
      Output: {"intent": "book", "entities": {"date": "2026-05-15", "time": "09:30", "treatment": "check-up"}}

      Input: "Can I book whitening for tomorrow at 11am"
      Output: {"intent": "book", "entities": {"date": "#{(today + 1).iso8601}", "time": "11:00", "treatment": "whitening"}}

      Input: "My name is Jane Doe, phone 0712345678, new patient. 20 May at 2pm cosmetic"
      Output: {"intent": "book", "entities": {"date": "2026-05-20", "time": "14:00", "treatment": "cosmetic consultation", "name": "Jane Doe"}}

      Input: "What time do you open?"
      Output: {"intent": "faq", "entities": {}}

      Input: "I have severe pain, this is urgent"
      Output: {"intent": "urgent", "entities": {}}

      Input: "Please reschedule to Friday 09:30"
      Output: {"intent": "reschedule", "entities": {"date": "2026-05-15", "time": "09:30"}}

      Input: "yes please confirm"
      Output: {"intent": "confirm", "entities": {}}

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
  # `channel` is forwarded to PromptBuilder so voice-channel callers can
  # receive a voice-tuned prompt (PR 2). Defaults to :whatsapp.
  def build_system_prompt(patient: nil, context: {}, channel: :whatsapp)
    PromptBuilder.new(patient: patient, context: context, channel: channel).build
  end

  # Picks the Claude model for a given channel. Voice prioritises latency
  # (Haiku 4.5); WhatsApp prioritises quality (Sonnet 4.6). Unknown
  # channels fall back to the default Sonnet — safer for routine work.
  def model_for(channel)
    MODELS_PER_CHANNEL[channel.to_sym] || DEFAULT_MODEL
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
