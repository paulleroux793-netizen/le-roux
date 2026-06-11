# Anonymous website-visitor chat session — the web equivalent of a WhatsApp Conversation.
# Stores conversation memory (jsonb) so the SAME booking AI gets multi-turn context, plus the
# captured booking fields. Mirrors Conversation#add_messages exactly, so AiService's existing
# last-20 memory window works unchanged for the web channel. Visitor phone is encrypted (POPIA).
class WebChatSession < ApplicationRecord
  belongs_to :patient, optional: true
  encrypts :visitor_phone, deterministic: true

  STATUSES = %w[active booked closed].freeze

  validates :session_id, presence: true, uniqueness: true
  validates :status, inclusion: { in: STATUSES }

  # --- memory (identical shape to Conversation#messages so AiService is reused as-is) ---
  def add_messages(entries)
    self.messages ||= []
    entries.each do |e|
      self.messages << {
        "role"      => (e[:role] || e["role"]).to_s,
        "content"   => (e[:content] || e["content"]).to_s,
        "timestamp" => (e[:timestamp] || Time.current).iso8601
      }
    end
    self.last_seen_at = Time.current
    save!
  end

  def add_message(role:, content:, timestamp: Time.current)
    add_messages([ { role: role, content: content, timestamp: timestamp } ])
  end

  def consented? = whatsapp_consent_at.present?
  def booked!     = update!(status: "booked")
end
