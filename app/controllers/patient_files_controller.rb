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

  # POST — send the patient their WhatsApp intake link (creates the pending
  # FormSubmissions + a signed 14-day link). Reply on the line they messaged from
  # if known; otherwise IntakeDispatch falls back to the env WhatsApp number.
  def send_intake
    patient = Patient.find(params[:patient_id])
    IntakeDispatch.call(patient)
    # 303 See Other so Inertia issues a fresh GET instead of replaying this POST.
    redirect_to patient_file_path(patient), notice: "Intake link sent to #{patient.phone}.", status: :see_other
  rescue IntakeDispatch::Error => e
    redirect_to patient_file_path(patient), alert: "Could not send intake link: #{e.message}", status: :see_other
  end

  # GET — the printable, pre-filled intake pack for reception to print on arrival.
  # Blank signature/initial blocks; the patient signs by hand (print-and-sign).
  def intake_pdf
    patient = Patient.find(params[:patient_id])
    send_data IntakePdf.new(patient).render,
              filename: "intake-#{patient.id}-#{patient.last_name.parameterize}.pdf",
              type: "application/pdf",
              disposition: "inline"
  end

  private

  def doc_props(d)
    {
      id: d.id, title: d.title, doc_type: d.doc_type, source: d.source,
      signed: d.signed, file_name: d.file_name, captured_at: d.captured_at.iso8601
    }
  end
end
