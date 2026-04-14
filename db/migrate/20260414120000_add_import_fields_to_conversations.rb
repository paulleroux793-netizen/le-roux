class AddImportFieldsToConversations < ActiveRecord::Migration[8.0]
  # Phase 10 — Import Historical WhatsApp Chats.
  #
  # Adds four columns to the existing conversations table so imported
  # threads can live alongside live webhook-ingested ones:
  #
  #   source       — "live" (default) for webhook-created rows, "import"
  #                  for historical chats brought in via the importer.
  #                  Keeps the existing flow untouched via the default.
  #   topic        — short human-readable label summarising what the
  #                  conversation was about (e.g. "Appointment booking").
  #                  Populated by WhatsappTopicClassifier at import time.
  #   imported_at  — timestamp of the import run, so an operator can
  #                  trace a row back to a specific upload.
  #   external_id  — stable per-thread key (sha of file path + sender
  #                  phone). Unique index makes re-running the importer
  #                  idempotent — the same export file will update the
  #                  existing row instead of creating a duplicate.
  def change
    add_column :conversations, :source,      :string,   null: false, default: "live"
    add_column :conversations, :topic,       :string
    add_column :conversations, :imported_at, :datetime
    add_column :conversations, :external_id, :string

    add_index :conversations, :source
    add_index :conversations, :external_id, unique: true
  end
end
