# Public, tokenised patient intake wizard. The link sent over WhatsApp carries a
# signed_id for the Patient (purpose: :intake, 14-day expiry) — no PII in the URL,
# unguessable, self-expiring. On open we mark the patient's pending intake forms
# "opened"; on submit we file each one (FormSubmission#complete!) and sync the handy
# denormalised fields onto the patient + medical history.
#
# Print-and-sign: nothing is signed here. Reception prints IntakePdf on arrival.
class IntakesController < PublicController
  # The bundle of templates that make up "the intake".
  KEYS = %w[patient_details health_questionnaire consent_treatment].freeze

  def show
    patient = patient_from_token
    return render_invalid unless patient

    submissions = IntakeProcessor.pending_or_recent(patient)
    submissions.each { |s| s.update!(status: "opened", opened_at: Time.current) if s.status == "sent" }

    render inertia: "PublicIntake", props: {
      token: params[:token],
      patient: { first_name: patient.first_name, last_name: patient.last_name },
      practice: { name: "Dr Chalita le Roux Inc" },
      privacy_notice: IntakePrivacyNotice.sections,
      completed: submissions.any? && submissions.all? { |s| s.status == "completed" },
      templates: submissions.map { |s|
        { key: s.form_template.key, name: s.form_template.name, schema: s.form_template.schema }
      }
    }
  end

  def update
    patient = patient_from_token
    return render_invalid unless patient

    answers = params.require(:answers).permit!.to_h
    IntakeProcessor.new(patient, answers).save!

    # Inertia requires 303 See Other on a non-GET redirect so the browser issues a
    # fresh GET to the intake page instead of replaying the PATCH against it.
    redirect_to intake_path(token: params[:token]), status: :see_other
  end

  private

  # Returns the Patient for a valid, unexpired token, or nil.
  def patient_from_token
    Patient.find_signed(params[:token], purpose: :intake)
  rescue ActiveSupport::MessageVerifier::InvalidSignature
    nil
  end

  def render_invalid
    render inertia: "PublicIntake", props: { token: nil, invalid: true }
  end
end
