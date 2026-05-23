# N2 — Mailbox integration scaffold (Outlook-style unified inbox for the dental dashboard).
#
# Design driven by the 2026-05-23 Perplexity research:
#   - Use Aurinko (or similar managed email API) as the unified provider so we
#     don't have to deal with Microsoft Graph + Gmail API + IMAP individually.
#     POPIA-compliant + African data centers. ENV: MAIL_PROVIDER=aurinko.
#   - Hybrid storage: metadata in Postgres for fast indexing + patient mapping;
#     full bodies + attachments in Active Storage. This migration creates the
#     PG side; attachment storage comes online when we wire the provider.
#   - Threading reconciliation in app code, NOT at the provider — so Gmail's
#     subject-based threading doesn't merge distinct appointment requests
#     into a single conversation.
#   - Mail message → patient mapping is best-effort; we never auto-attach if
#     match confidence < 0.95 (manual review queue otherwise).
class CreateMailAccountsThreadsAndMessages < ActiveRecord::Migration[8.1]
  def change
    create_table :mail_accounts do |t|
      # Provider keys: "aurinko", "microsoft_graph", "gmail_api", "imap" (legacy)
      t.string :provider, null: false
      t.string :address, null: false                 # the email address itself
      t.string :display_name                          # "Practice Info" / "Paul Personal"
      # Aurinko-style account ID, or our own UUID if direct OAuth flow.
      t.string :external_account_id
      # Encrypted OAuth tokens via Rails' encrypts macro on the model.
      t.text :oauth_access_token_ciphertext
      t.text :oauth_refresh_token_ciphertext
      t.datetime :oauth_expires_at
      # Sync metadata
      t.string :status, null: false, default: "connecting"  # connecting / active / error / disabled
      t.text :status_message                                 # last error if status=error
      t.datetime :last_synced_at
      t.string :webhook_secret                               # provider-signed webhook signature
      t.timestamps
      t.index :address, unique: true
      t.index :status
    end

    create_table :mail_threads do |t|
      t.references :mail_account, null: false, foreign_key: true
      # Provider's own thread id (Aurinko thread, Gmail thread, Microsoft conversation id).
      # Combined with mail_account_id this is unique.
      t.string :provider_thread_id, null: false
      t.string :subject
      t.string :participants, array: true, default: []
      t.integer :message_count, default: 0, null: false
      t.integer :unread_count, default: 0, null: false
      t.datetime :last_message_at
      t.boolean :starred, default: false, null: false
      t.boolean :archived, default: false, null: false
      t.boolean :trashed, default: false, null: false
      # Best-effort linkage to a patient (NULL = unmatched). We never auto-link
      # if confidence < 0.95; the unmatched ones go to a triage queue.
      t.references :patient, foreign_key: true, null: true
      t.decimal :patient_match_confidence, precision: 4, scale: 3 # 0.000–1.000
      # Inferred clinical intent (appointment_request, insurance_inquiry,
      # treatment_question, billing_issue, other). Populated by the AI classifier.
      t.string :clinical_intent
      t.timestamps
      t.index [ :mail_account_id, :provider_thread_id ], unique: true, name: "idx_mail_threads_on_account_and_provider_id"
      t.index :last_message_at
      t.index :clinical_intent
    end

    create_table :mail_messages do |t|
      t.references :mail_thread, null: false, foreign_key: true
      t.references :mail_account, null: false, foreign_key: true
      t.string :provider_message_id, null: false      # for idempotency on webhook re-delivery
      t.string :message_id_header                      # the RFC 5322 Message-ID
      t.string :from_address, null: false
      t.string :from_name
      t.string :to_addresses, array: true, default: []
      t.string :cc_addresses, array: true, default: []
      t.string :subject
      t.text :snippet                                  # short preview (~200 chars)
      t.text :body_text                                # plain-text rendition
      t.text :body_html                                # HTML rendition (sanitised before display)
      t.datetime :received_at, null: false
      t.datetime :read_at                              # null = unread
      t.boolean :starred, default: false, null: false
      t.boolean :sent_by_us, default: false, null: false # outgoing message we composed
      t.boolean :has_attachments, default: false, null: false
      t.boolean :flagged_phi, default: false, null: false # AI detected likely PHI; quarantine path
      t.timestamps
      t.index [ :mail_account_id, :provider_message_id ], unique: true, name: "idx_mail_messages_on_account_and_provider_id"
      t.index :received_at
    end

    # AI-extracted appointment draft (human-in-the-loop) tied back to a mail message.
    # Per the research: never auto-create appointments; always present as
    # "ready-to-confirm" cards in the inbox reading pane.
    create_table :mail_appointment_drafts do |t|
      t.references :mail_message, null: false, foreign_key: true
      t.references :patient, foreign_key: true, null: true
      t.datetime :requested_start_time
      t.integer :requested_duration_minutes
      t.string :requested_reason
      t.decimal :confidence, precision: 4, scale: 3  # 0.000–1.000
      t.string :status, null: false, default: "pending"  # pending / confirmed / dismissed
      t.jsonb :extraction_metadata, default: {}, null: false  # which fields the AI extracted with what confidence
      t.references :confirmed_appointment, foreign_key: { to_table: :appointments }, null: true
      t.timestamps
      t.index :status
    end
  end
end
