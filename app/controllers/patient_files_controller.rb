# The patient's digital file — folders + documents + forms + notepad. Replaces the 5 physical files.
# Additive: a NEW route/page; the existing PatientShow page is untouched. (Ivory, Phase 4.)
class PatientFilesController < ApplicationController
  def show
    patient = Patient.find(params[:patient_id])
    documents = patient.documents.order(captured_at: :desc).to_a
    forms = patient.form_submissions.includes(:form_template).order(created_at: :desc).limit(20)
    notes = patient.notepad_pages.order(created_at: :desc).limit(20)

    render inertia: "PatientFile", props: {
      patient: { id: patient.id, name: patient.full_name, phone: patient.phone },
      folders: Document::FOLDERS.map { |f|
        docs = documents.select { |d| d.folder == f }
        { key: f, label: Document::FOLDER_LABELS[f], count: docs.size,
          documents: docs.map { |d| doc_props(d) } }
      },
      forms: forms.map { |s|
        { id: s.id, name: s.form_template.name, status: s.status,
          sent_at: s.sent_at&.iso8601, completed_at: s.completed_at&.iso8601, signed: s.signature_data.present? }
      },
      notes: notes.map { |n| { id: n.id, title: n.title, content: n.content, filed: n.document_id.present?, created_by: n.created_by, created_at: n.created_at.iso8601 } }
    }
  end

  private

  def doc_props(d)
    {
      id: d.id, title: d.title, doc_type: d.doc_type, source: d.source,
      signed: d.signed, file_name: d.file_name, captured_at: d.captured_at.iso8601
    }
  end
end
