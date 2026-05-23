# N1 + N3 scaffold migration.
#
# N1 — multi-device recording: every dental practice will have multiple
#      labelled microphones (Surgery 1, Surgery 2, Reception). The
#      always-on scribe needs to know WHERE a transcript came from so
#      summaries can be tied back to the patient who was in the chair
#      at that moment. ScribeSession gains a recording_device_id.
#
# N3 — end-of-appointment summary: structured digest produced by an
#      LLM over the scribe transcript. We keep this as columns on the
#      `appointments` table (not a separate model) because there's
#      strictly one summary per appointment and they're always loaded
#      together. JSONB for the patient_questions array keeps schema
#      lean while permitting future fields.
class CreateAppointmentSummariesAndRecordingDevices < ActiveRecord::Migration[8.1]
  def change
    # ── N1 ────────────────────────────────────────────────────────
    create_table :recording_devices do |t|
      t.string :name, null: false                # e.g. "Surgery 1"
      t.string :location, null: false             # surgery_1 / surgery_2 / reception
      t.boolean :enabled, null: false, default: true
      t.datetime :last_seen_at
      # Free-form, e.g. "Yealink AVM-X-3 in chair-side cabinet".
      t.text :notes
      t.timestamps
      t.index :name, unique: true
      t.index :location
    end

    add_reference :scribe_sessions, :recording_device, foreign_key: true, null: true

    # ── N3 ────────────────────────────────────────────────────────
    add_column :appointments, :summary_decisions_text, :text
    # JSONB array of {q: "...", a: "..."} objects, or {} when empty.
    add_column :appointments, :summary_patient_questions, :jsonb, default: [], null: false
    add_column :appointments, :summary_estimate_intent_text, :text
    # When the LLM finished + which session it summarised.
    add_column :appointments, :summary_generated_at, :datetime
    add_reference :appointments, :summary_scribe_session,
                  foreign_key: { to_table: :scribe_sessions },
                  null: true

    add_index :appointments, :summary_generated_at
  end
end
