# Phase 7 (P7.3) audit fix #19 — make cross-child FKs nullify on delete so destroying a patient
# (which cascades to documents/estimates/COTs) can never hit an FK-ordering error.
class AuditFkOnDeleteNullify < ActiveRecord::Migration[8.1]
  def up
    remove_foreign_key :form_submissions, :documents
    add_foreign_key    :form_submissions, :documents, on_delete: :nullify

    remove_foreign_key :notepad_pages, :documents
    add_foreign_key    :notepad_pages, :documents, on_delete: :nullify

    remove_foreign_key :scribe_sessions, :estimates
    add_foreign_key    :scribe_sessions, :estimates, on_delete: :nullify

    remove_foreign_key :scribe_sessions, :courses_of_treatment, column: :course_of_treatment_id
    add_foreign_key    :scribe_sessions, :courses_of_treatment, column: :course_of_treatment_id, on_delete: :nullify
  end

  def down
    [ [ :form_submissions, :documents ], [ :notepad_pages, :documents ], [ :scribe_sessions, :estimates ] ].each do |from, to|
      remove_foreign_key from, to
      add_foreign_key from, to
    end
    remove_foreign_key :scribe_sessions, :courses_of_treatment, column: :course_of_treatment_id
    add_foreign_key    :scribe_sessions, :courses_of_treatment, column: :course_of_treatment_id
  end
end
