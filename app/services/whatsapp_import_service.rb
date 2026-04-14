require "digest"
require "json"

class WhatsappImportService
  # Phase 10 — Historical WhatsApp chat importer.
  #
  # Reads a chat export off disk or from an uploaded IO and hydrates
  # Conversation + Patient rows. Two on-disk formats are supported:
  #
  #   1. **JSON** (preferred — structured, unambiguous). An array of
  #      thread objects. Operator tooling is expected to transform
  #      whatever source system they have into this shape:
  #
  #        [
  #          {
  #            "phone":      "+27831234567",
  #            "name":       "Emily Clark",         # optional — phone is fallback
  #            "topic":      "Appointment booking", # optional — classifier runs if absent
  #            "started_at": "2024-01-15T10:23:00Z",
  #            "messages": [
  #              { "from": "patient", "text": "Hi, I'd like to book",
  #                "timestamp": "2024-01-15T10:23:00Z" },
  #              { "from": "clinic",  "text": "Sure — Tuesday at 10?",
  #                "timestamp": "2024-01-15T10:24:00Z" }
  #            ]
  #          }
  #        ]
  #
  #      `from` values: "patient" → role "user", "clinic" → "assistant".
  #
  #   2. **TXT** (WhatsApp mobile "Export chat" feature). Handles the
  #      two mainstream line formats:
  #
  #        [2024-01-15, 10:23:45] Emily Clark: Hi, I'd like to book
  #        15/01/2024, 10:23 - Emily Clark: Hi, I'd like to book
  #
  #      Continuation lines (no timestamp prefix) are appended to the
  #      previous message. The .txt flow requires the caller to supply
  #      `patient_phone:` and `owner_name:` — messages whose sender
  #      matches `owner_name` are tagged as "assistant"; everyone else
  #      becomes "user".
  #
  # Idempotency: each imported thread gets a deterministic
  # `external_id` (sha1 of source + identifying key). A second run of
  # the same export updates the existing Conversation row instead of
  # creating a duplicate, so operators can safely re-run after fixing
  # an input file.
  class ImportError < StandardError; end

  Result = Struct.new(:created, :updated, :skipped, :errors, keyword_init: true) do
    def total = created + updated
  end

  def self.import_file(path, owner_name: nil, patient_phone: nil)
    raise ImportError, "file not found: #{path}" unless File.exist?(path)

    content = File.read(path)
    source_key = File.basename(path)
    ext = File.extname(path).downcase

    if ext == ".json"
      new(source_key: source_key).import_json(content)
    else
      new(source_key: source_key).import_txt(
        content, owner_name: owner_name, patient_phone: patient_phone
      )
    end
  end

  def self.import_upload(uploaded_file, owner_name: nil, patient_phone: nil)
    content    = uploaded_file.read
    source_key = uploaded_file.original_filename.to_s
    ext        = File.extname(source_key).downcase

    if ext == ".json"
      new(source_key: source_key).import_json(content)
    else
      new(source_key: source_key).import_txt(
        content, owner_name: owner_name, patient_phone: patient_phone
      )
    end
  end

  def initialize(source_key:)
    @source_key = source_key
    @result = Result.new(created: 0, updated: 0, skipped: 0, errors: [])
  end

  # ── JSON path ─────────────────────────────────────────────────────
  def import_json(content)
    threads =
      begin
        JSON.parse(content)
      rescue JSON::ParserError => e
        raise ImportError, "invalid JSON: #{e.message}"
      end

    raise ImportError, "JSON root must be an array of threads" unless threads.is_a?(Array)

    threads.each_with_index do |thread, idx|
      begin
        persist_thread(
          phone:    thread["phone"],
          name:     thread["name"],
          topic:    thread["topic"],
          started:  thread["started_at"],
          messages: normalize_json_messages(thread["messages"])
        )
      rescue => e
        @result.skipped += 1
        @result.errors << "thread ##{idx}: #{e.message}"
      end
    end

    @result
  end

  # ── TXT path ──────────────────────────────────────────────────────
  def import_txt(content, owner_name:, patient_phone:)
    raise ImportError, "TXT imports require patient_phone" if patient_phone.blank?
    raise ImportError, "TXT imports require owner_name"    if owner_name.blank?

    messages, sender_name = parse_txt_messages(content, owner_name: owner_name)
    return @result if messages.empty?

    begin
      persist_thread(
        phone:    patient_phone,
        name:     sender_name,
        topic:    nil,
        started:  messages.first[:timestamp],
        messages: messages
      )
    rescue => e
      @result.skipped += 1
      @result.errors << e.message
    end
    @result
  end

  private

  # Shape normalisation: JSON input → internal role/content/timestamp
  def normalize_json_messages(raw)
    Array(raw).map do |m|
      from = m["from"].to_s.downcase
      role = from == "clinic" ? "assistant" : "user"
      {
        role:      role,
        content:   m["text"].to_s,
        timestamp: parse_time(m["timestamp"]) || Time.current
      }
    end
  end

  # TXT parser — returns [messages, best_guess_non_owner_name].
  # Supports bracketed (iOS) and dashed (Android) header lines, plus
  # multi-line messages (continuation lines get appended).
  IOS_HEADER_RE     = /\A\[(?<date>\d{1,4}[\/\-\.]\d{1,2}[\/\-\.]\d{1,4}),?\s+(?<time>\d{1,2}:\d{2}(?::\d{2})?)\]\s+(?<sender>[^:]+?):\s?(?<body>.*)\z/
  ANDROID_HEADER_RE = /\A(?<date>\d{1,4}[\/\-\.]\d{1,2}[\/\-\.]\d{1,4}),?\s+(?<time>\d{1,2}:\d{2}(?:\s?[ap]m)?)\s*[-–]\s*(?<sender>[^:]+?):\s?(?<body>.*)\z/i

  def parse_txt_messages(content, owner_name:)
    messages   = []
    last_other = nil

    content.each_line do |line|
      line = line.sub(/\A\u{200E}/, "").rstrip # strip LRM + trailing \r\n
      next if line.empty?

      m = line.match(IOS_HEADER_RE) || line.match(ANDROID_HEADER_RE)
      if m
        sender = m[:sender].strip
        body   = m[:body].to_s

        # WhatsApp system lines ("Messages and calls are end-to-end
        # encrypted…", "<Media omitted>", etc.) have no real sender
        # or are noise — drop them.
        next if body.strip == "<Media omitted>"

        role = sender.casecmp(owner_name.to_s).zero? ? "assistant" : "user"
        last_other = sender if role == "user"

        messages << {
          role:      role,
          content:   body,
          timestamp: parse_time("#{m[:date]} #{m[:time]}") || Time.current,
          _sender:   sender
        }
      elsif messages.any?
        # Continuation line — append to previous message with a newline.
        messages.last[:content] = "#{messages.last[:content]}\n#{line}"
      end
    end

    # Drop the internal _sender key before returning.
    messages.each { |msg| msg.delete(:_sender) }
    [messages, last_other]
  end

  def persist_thread(phone:, name:, topic:, started:, messages:)
    raise "phone missing" if phone.blank?
    raise "messages empty" if messages.empty?

    normalized_phone = normalize_phone(phone)
    patient = find_or_create_patient(normalized_phone, name)

    ext_id  = Digest::SHA1.hexdigest("#{@source_key}|#{normalized_phone}")
    text    = messages.map { |m| m[:content] }.join("\n")
    label   = topic.presence || WhatsappTopicClassifier.classify(text)
    started_at = parse_time(started) || messages.first[:timestamp] || Time.current
    ended_at   = messages.last[:timestamp] || started_at

    convo = Conversation.find_or_initialize_by(external_id: ext_id)
    is_new = convo.new_record?

    convo.assign_attributes(
      patient:     patient,
      channel:     "whatsapp",
      status:      "closed",
      source:      "import",
      topic:       label,
      started_at:  started_at,
      ended_at:    ended_at,
      imported_at: Time.current,
      messages:    messages.map { |m|
        { role: m[:role], content: m[:content], timestamp: m[:timestamp].iso8601 }
      }
    )
    convo.save!

    is_new ? (@result.created += 1) : (@result.updated += 1)
  end

  def find_or_create_patient(phone, display_name)
    patient = Patient.find_by(phone: phone)
    return patient if patient

    first, last = split_name(display_name, phone)
    Patient.create!(first_name: first, last_name: last, phone: phone)
  end

  def split_name(display_name, phone_fallback)
    name = display_name.to_s.strip
    return ["Unknown", phone_fallback] if name.blank?

    parts = name.split(/\s+/, 2)
    [parts.first, parts[1].presence || "(imported)"]
  end

  def normalize_phone(phone)
    cleaned = phone.to_s.gsub(/[\s\-\(\)]/, "")
    cleaned.start_with?("+") ? cleaned : "+#{cleaned}"
  end

  def parse_time(value)
    return value if value.is_a?(Time) || value.is_a?(ActiveSupport::TimeWithZone)
    return nil if value.blank?
    Time.zone.parse(value.to_s)
  rescue ArgumentError
    nil
  end
end
