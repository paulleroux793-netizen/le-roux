# 2026-05-24 — POPIA consent flag on patients.
#
# Paul gets consent for AI processing on the practice's existing PAPER
# consent form. The receptionist files the signed form physically; the
# system needs to know the consent exists so AI features (scribe
# summary, mailbox booking drafts) can self-gate.
#
# Default: nil (no consent on file). AI features must check this column
# is set before processing the patient's data. Receptionist ticks the
# checkbox in the patient profile after filing the paper form.
class AddConsentToAiProcessingToPatients < ActiveRecord::Migration[8.1]
  def change
    add_column :patients, :consent_to_ai_processing_at, :datetime
    add_column :patients, :consent_to_ai_processing_by, :string  # name of receptionist who ticked the box
    add_index  :patients, :consent_to_ai_processing_at
  end
end
