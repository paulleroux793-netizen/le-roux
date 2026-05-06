class AddAiPausedUntilToConversations < ActiveRecord::Migration[8.1]
  # Reception takeover detection. When reception sends a manual reply via
  # the dashboard (`POST /conversations/:id/reply`), set ai_paused_until =
  # Time.current + 4.hours. WhatsappService#handle_incoming bails early if
  # the timestamp is in the future, so the AI does not contradict
  # reception's nuanced human reply on the next inbound message.
  #
  # Reception can manually clear the pause from the dashboard ("hand back
  # to AI") if the conversation is resolved sooner. After the timestamp
  # passes, the AI resumes normally.
  #
  # See CODE_LOCKED_GUARDRAILS §8.2.
  def change
    add_column :conversations, :ai_paused_until, :datetime
    add_index  :conversations, :ai_paused_until, where: "ai_paused_until IS NOT NULL"
  end
end
