class CreateWebhookReceipts < ActiveRecord::Migration[8.1]
  # Bulletproof idempotency for inbound provider webhooks. Twilio delivers
  # webhooks AT-LEAST-ONCE (it retries the same MessageSid if our endpoint is
  # slow or errors), so we must dedupe. A unique index on the provider's event
  # SID is the recommended pattern — stronger than a cache TTL, which can miss.
  def change
    create_table :webhook_receipts do |t|
      t.string :event_sid, null: false
      t.string :event_type
      t.datetime :created_at, null: false
    end
    add_index :webhook_receipts, :event_sid, unique: true
  end
end
