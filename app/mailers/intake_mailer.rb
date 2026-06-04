# Emails the practice the completed intake pack the moment a patient finishes the
# online forms, so reception can print it and add it to the patient's file when they
# arrive. This is the interim delivery mechanism — the diary / account auto-linking
# lands later, once Ivory accounts are fully running.
class IntakeMailer < ApplicationMailer
  def completed(patient)
    @patient = patient

    attachments[pdf_filename(patient)] = {
      mime_type: "application/pdf",
      content: IntakePdf.new(patient).render
    }

    mail(
      to: ENV.fetch("INTAKE_NOTIFY_EMAIL", "info@drchalitaleroux.co.za"),
      subject: "New patient forms completed — #{patient.full_name}"
    )
  end

  private

  def pdf_filename(patient)
    "intake-#{patient.id}-#{patient.last_name.parameterize.presence || 'patient'}.pdf"
  end
end
