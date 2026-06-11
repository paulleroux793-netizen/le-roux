class CreateWebChatSessions < ActiveRecord::Migration[8.1]
  def change
    create_table :web_chat_sessions do |t|
      t.string   :session_id, null: false
      t.jsonb    :messages, null: false, default: []
      t.references :patient, null: true, foreign_key: true
      t.string   :status, null: false, default: "active"
      t.string   :visitor_name
      t.text     :visitor_phone           # encrypted at rest (POPIA)
      t.datetime :whatsapp_consent_at
      t.string   :reason
      t.string   :source, null: false, default: "web_chat"
      t.string   :language, default: "en"
      t.datetime :last_seen_at
      t.timestamps
    end
    add_index :web_chat_sessions, :session_id, unique: true
    add_index :web_chat_sessions, :status
  end
end
