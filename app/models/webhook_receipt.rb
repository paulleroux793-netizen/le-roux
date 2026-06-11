# A record that a given provider webhook event (by its unique SID) has been
# accepted for processing. The unique index on event_sid makes duplicate
# delivery a no-op: the second insert raises RecordNotUnique and the caller
# skips re-processing. See Webhooks::WhatsappController#incoming.
class WebhookReceipt < ApplicationRecord
  # Returns true the FIRST time a sid is seen, false on any duplicate.
  def self.first_seen?(sid, type:)
    return true if sid.blank?
    create!(event_sid: sid, event_type: type)
    true
  rescue ActiveRecord::RecordNotUnique
    false
  end
end
