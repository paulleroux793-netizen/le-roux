# A digital notepad page — Dr Chalita writes/annotates here instead of on paper; a snapshot can
# be filed to the patient's digital file as a Document.
class NotepadPage < ApplicationRecord
  belongs_to :patient
  belongs_to :course_of_treatment, optional: true
  belongs_to :document, optional: true

  validates :title, presence: true

  # File a snapshot of this note into the patient's digital file.
  def file_to_patient_file!(by: nil)
    doc = Document.create!(patient_id: patient_id, course_of_treatment_id: course_of_treatment_id,
      folder: "correspondence", title: title, doc_type: "note", source: "notepad",
      uploaded_by: by, captured_at: Time.current, notes: content)
    update!(document: doc)
    doc
  end
end
