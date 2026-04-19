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
end
