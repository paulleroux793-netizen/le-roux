# Phase 6 (P6.1/6.2) — AI chair-side scribe. ADDITIVE ONLY.
# A scribe session binds to an in-chair appointment; a local transcript is drafted into a
# proposed course of treatment + estimate that Dr Chalita REVIEWS (never auto-billed).
class CreateScribeSessions < ActiveRecord::Migration[8.1]
  def change
    create_table :scribe_sessions do |t|
      t.bigint  :patient_id, null: false
      t.bigint  :appointment_id                   # the in-chair appointment that triggered it
      t.bigint  :course_of_treatment_id           # the COT it drafted (once reviewed)
      t.bigint  :estimate_id                       # the proposed estimate (draft) for review
      t.string  :status, null: false, default: "recording"  # recording / transcribing / drafted / reviewed / discarded
      t.text :transcript                       # local Whisper transcript (audio never leaves the PC)
      t.jsonb :draft, null: false, default: {}    # extracted findings + proposed line items
      t.datetime :started_at
      t.datetime :ended_at
      t.text     :notes
      t.timestamps
      t.index :patient_id
      t.index :appointment_id
      t.index :status
    end

    add_foreign_key :scribe_sessions, :patients
    add_foreign_key :scribe_sessions, :appointments
    add_foreign_key :scribe_sessions, :courses_of_treatment, column: :course_of_treatment_id
    add_foreign_key :scribe_sessions, :estimates
  end
end
