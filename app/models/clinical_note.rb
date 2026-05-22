# A SOAP clinical note. Append-only for HPCSA integrity: once signed it locks, and a
# correction is a NEW note that `supersedes` the original (never an in-place edit).
class ClinicalNote < ApplicationRecord
  belongs_to :patient
  belongs_to :course_of_treatment, optional: true
  belongs_to :supersedes, class_name: "ClinicalNote", optional: true
  has_one :superseded_by, class_name: "ClinicalNote", foreign_key: :supersedes_id

  before_update :prevent_locked_edit

  def sign!(by:)
    update!(signed_by: by, signed_at: Time.current, locked: true)
  end

  # Create a correcting note that supersedes this (locked) one.
  def amend(attrs, by:)
    ClinicalNote.create!(attrs.merge(patient_id: patient_id, course_of_treatment_id: course_of_treatment_id, supersedes_id: id))
  end

  private

  def prevent_locked_edit
    # Allow only the signing transition to mutate a locked note; block all other edits.
    return unless locked_was && (changes.keys - %w[signed_by signed_at locked updated_at]).any?
    errors.add(:base, "Signed clinical notes are immutable; create an amendment instead")
    throw(:abort)
  end
end
