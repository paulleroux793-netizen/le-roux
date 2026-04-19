class AfrikaansDatasetService
  DATASET_PATH = Rails.root.join("config", "ai", "afrikaans_language_dataset.json").freeze

  # Topics most relevant to a dental/medical booking context.
  # Used to bias example selection toward on-topic Afrikaans phrasing.
  HEALTH_TOPICS = %w[
    Health\ and\ Wellness
    Work\ or\ Career
    Family\ and\ Relationships
    Education
  ].freeze

  # Intent → preferred topic groups for contextual example selection.
  INTENT_TOPICS = {
    "book"       => %w[Health\ and\ Wellness Work\ or\ Career Family\ and\ Relationships],
    "reschedule" => %w[Health\ and\ Wellness Work\ or\ Career],
    "cancel"     => %w[Health\ and\ Wellness Work\ or\ Career],
    "urgent"     => %w[Health\ and\ Wellness],
    "faq"        => %w[Health\ and\ Wellness Finance\ and\ Economy],
    "confirm"    => %w[Health\ and\ Wellness Family\ and\ Relationships]
  }.freeze

  class << self
    # Returns N examples relevant to the given intent.
    # Falls back to random_examples if no intent match or service unavailable.
    def examples_for_intent(intent, limit: 6)
      topics = INTENT_TOPICS[intent] || HEALTH_TOPICS
      pool = records.select { |r| topics.any? { |t| r["topic"] == t } }
      pool = records if pool.empty?
      pool.sample(limit).map { |r| { af: r["afrikaans"], en: r["english"] } }
    rescue StandardError => e
      Rails.logger.warn("[AfrikaansDataset] examples_for_intent failed: #{e.message}")
      fallback_examples
    end

    # Returns N random examples from the full dataset (any topic).
    def random_examples(limit: 8)
      records.sample(limit).map { |r| { af: r["afrikaans"], en: r["english"] } }
    rescue StandardError => e
      Rails.logger.warn("[AfrikaansDataset] random_examples failed: #{e.message}")
      fallback_examples
    end

    # Total number of usable records loaded.
    def size
      records.length
    end

    # Reload the dataset (useful in tests or after file changes).
    def reload!
      @records = nil
    end

    private

    def records
      @records ||= load_records
    end

    def load_records
      unless DATASET_PATH.exist?
        Rails.logger.warn("[AfrikaansDataset] Dataset file not found: #{DATASET_PATH}")
        return []
      end

      raw = JSON.parse(DATASET_PATH.read)
      all = Array(raw["records"])

      # Keep only records where both fields are present and Afrikaans was validated
      all.select do |r|
        r["afrikaans"].present? &&
          r["english"].present? &&
          r["gpt_evaluation_of_afrikaans"] == "Yes"
      end
    rescue JSON::ParserError => e
      Rails.logger.error("[AfrikaansDataset] JSON parse error: #{e.message}")
      []
    end

    def fallback_examples
      [
        { af: "Dit is belangrik om gereeld 'n dokter te besoek.", en: "It is important to visit a doctor regularly." },
        { af: "Gesondheid is ons grootste bate.", en: "Health is our greatest asset." },
        { af: "Goeie higiëne help om siektes te voorkom.", en: "Good hygiene helps prevent diseases." }
      ]
    end
  end
end
