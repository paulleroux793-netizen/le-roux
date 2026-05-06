class Conversation < ApplicationRecord
  SOURCES   = %w[live import].freeze
  LANGUAGES = %w[en af].freeze

  belongs_to :patient

  validates :channel, presence: true, inclusion: { in: %w[whatsapp voice] }
  validates :status, presence: true
  validates :source, presence: true, inclusion: { in: SOURCES }
  validates :external_id, uniqueness: true, allow_nil: true
  validates :language, inclusion: { in: LANGUAGES }, allow_nil: true

  scope :active, -> { where(status: "active") }
  scope :by_channel, ->(channel) { where(channel: channel) }
  scope :recent, -> { order(updated_at: :desc) }
  scope :live,     -> { where(source: "live") }
  scope :imported, -> { where(source: "import") }
  scope :tagged, ->(tag) { where("tags @> ?", [ tag ].to_json) }

  def add_message(role:, content:, timestamp: Time.current)
    add_messages([ { role: role, content: content, timestamp: timestamp } ])
  end

  def add_messages(entries)
    self.messages ||= []

    entries.each do |entry|
      self.messages << {
        role: entry.fetch(:role),
        content: entry.fetch(:content),
        timestamp: entry.fetch(:timestamp, Time.current).iso8601
      }
    end

    save!
  end

  def close!
    update!(status: "closed", ended_at: Time.current)
  end

  # ── Reception takeover (AI standby) ────────────────────────────────────
  # When reception sends a manual WhatsApp reply via the dashboard, the AI
  # must stop responding to that conversation for the configured pause
  # window so it doesn't contradict reception's nuanced human reply.
  # See CODE_LOCKED_GUARDRAILS §8.2.

  def ai_paused?
    ai_paused_until.present? && ai_paused_until > Time.current
  end

  def pause_ai!(duration: nil)
    duration ||= PracticeConfig.ai_pause_hours.hours
    update!(ai_paused_until: Time.current + duration)
  end

  def resume_ai!
    update!(ai_paused_until: nil)
  end
end
