# Public patient intake wizard. Two ways in:
#   1. Per-patient link  /intake/<signed_id>  — sent over WhatsApp to a KNOWN patient
#      (14-day expiry, no PII in URL). Pre-fills nothing the patient didn't type.
#   2. Generic shared link  /intake/new  — reception gives this to ANY patient; there's
#      no patient yet, so on submit we MATCH an existing record (by SA ID / passport or
#      phone) or CREATE a new one (reception reviews new self-registrations later).
#
# Print-and-sign: nothing is signed here. Reception prints IntakePdf on arrival.
class IntakesController < PublicController
  KEYS = %w[patient_details health_questionnaire consent_treatment].freeze
  GENERIC = "new" # the shareable link patients receive: /intake/new

  def show
    return render_wizard(nil) if params[:token] == GENERIC

    patient = patient_from_token
    return render_invalid unless patient

    render_wizard(patient)
  end

  def update
    return create_generic if params[:token] == GENERIC

    patient = patient_from_token
    return render_invalid unless patient

    IntakeProcessor.new(patient, intake_answers).save!
    redirect_to intake_path(token: params[:token]), status: :see_other
  end

  private

  # Render the wizard. For the generic link (patient = nil) there are no submissions
  # yet, so we render the active templates directly with a blank "Patient" greeting.
  def render_wizard(patient)
    if patient
      submissions = ensure_submissions(patient)
      completed = submissions.any? && submissions.all? { |s| s.status == "completed" }
      templates = submissions.map { |s| template_props(s.form_template) }
    else
      completed = false
      templates = KEYS.filter_map { |k| (t = FormTemplate.latest(k)) && template_props(t) }
    end

    render inertia: "PublicIntake", props: {
      token: params[:token],
      patient: { first_name: patient&.first_name.presence || "Patient", last_name: "" },
      practice: { name: "Dr Chalita le Roux Inc" },
      privacy_notice: IntakePrivacyNotice.sections,
      completed: completed,
      templates: templates
    }
  end

  # PATCH /intake/new — patient using the shared link. Match or create their record,
  # complete + email + file, then send them to their own short-lived link so they land
  # on the thank-you screen.
  def create_generic
    # Honeypot: a hidden field no human ever sees. Bots fill every field, so a non-blank
    # value means a bot — silently absorb it (no record, no email) and return the page.
    return redirect_to(intake_path(token: GENERIC), status: :see_other) if params[:website].present?

    answers = intake_answers
    patient = build_self_registration(answers["patient_details"] || {})
    patient.save!(validate: false) # deliberate: a NAME-bearing, review-flagged placeholder.
                                   # The real ID/phone live in the encrypted form data (and the
                                   # printed PDF), never written to the unique patient columns
                                   # from a public link — so a stranger can't collide/overwrite.

    KEYS.each do |key|
      template = FormTemplate.latest(key) or next
      next if patient.form_submissions.joins(:form_template)
                     .where(form_templates: { key: key }, status: %w[sent opened]).exists?

      patient.form_submissions.create!(form_template: template).mark_sent!
    end

    # self_registration: a public submission must NOT write the patient's identity/medical
    # columns — it only captures the (encrypted) form data and emails the pack.
    IntakeProcessor.new(patient, answers, self_registration: true).save!
    redirect_to intake_path(token: patient.signed_id(purpose: :intake, expires_in: 1.hour)),
                status: :see_other
  end

  # SECURITY: the public link must NEVER match or mutate an existing patient — a stranger
  # who knows a real patient's SA ID could otherwise overwrite their record (PHI integrity
  # + clinical-safety hazard). So we ALWAYS build a NEW, review-flagged record. Identity
  # columns are set ONLY when they don't collide with an existing patient (the unique
  # indexes would otherwise error, and we must never adopt someone else's row); either way
  # the real values are preserved in the form data. Reception verifies + merges from the
  # authenticated dashboard, where matching is a deliberate, audited action.
  def build_self_registration(pd)
    patient = Patient.new(
      first_name:    pd["first_name"].presence || "New",
      last_name:     pd["last_name"].presence  || "Patient",
      date_of_birth: pd["date_of_birth"].presence,
      notes:         self_registration_note + likely_duplicate_hint(pd).to_s
    )
    patient.email = pd["email"] if pd["email"].to_s.match?(URI::MailTo::EMAIL_REGEXP)

    id = pd["id_number"].to_s.strip
    patient.id_number = id if id.present? && !Patient.exists?(id_number: id)

    phone = pd["contact_number"].to_s.gsub(/\s+/, "")
    phone = "+#{phone}" if phone.present? && !phone.start_with?("+")
    patient.phone = phone if phone.present? && !Patient.exists?(phone: phone)

    patient
  end

  def self_registration_note
    "#{Patient::SELF_REG_MARKER} via the online intake link on #{Date.current.iso8601}. " \
      "The patient's ID/passport and phone are in the attached forms — verify their " \
      "identity and merge into their existing record if they are already in the system."
  end

  # Reception-only hint: does this self-registration LOOK like an existing patient? We never
  # auto-merge (security — see build_self_registration), but surfacing the likely match on the
  # placeholder lets reception verify + merge in one glance instead of creating a duplicate.
  def likely_duplicate_hint(pd)
    id    = pd["id_number"].to_s.strip
    phone = pd["contact_number"].to_s.gsub(/\s+/, "")
    first = pd["first_name"].to_s.downcase.strip
    last  = pd["last_name"].to_s.downcase.strip

    match   = (Patient.find_by(id_number: id) if id.present?)
    match ||= (Patient.where(phone: phone).first if phone.present? && phone.length >= 9)
    match ||= (Patient.where("LOWER(first_name) = ? AND LOWER(last_name) = ?", first, last).first if first.present? && last.present?)
    return nil unless match

    acct = match.account_code.present? ? " (account #{match.account_code})" : ""
    "\n\n⚠ LIKELY ALREADY IN SYSTEM: #{match.full_name}#{acct} — verify identity and MERGE " \
      "into that record rather than creating a duplicate."
  rescue StandardError => e
    Rails.logger.warn("[Intake] duplicate-hint failed: #{e.message}")
    nil
  end

  def ensure_submissions(patient)
    KEYS.filter_map do |key|
      template = FormTemplate.latest(key)
      next unless template

      sub = patient.form_submissions.joins(:form_template)
                   .where(form_templates: { key: key }).order(:created_at).last
      sub ||= patient.form_submissions.create!(form_template: template).tap(&:mark_sent!)
      sub.update!(status: "opened", opened_at: Time.current) if sub.status == "sent"
      sub
    end
  end

  def intake_answers
    params.require(:answers).permit!.to_h
  end

  def template_props(template)
    { key: template.key, name: template.name, schema: template.schema }
  end

  def patient_from_token
    Patient.find_signed(params[:token], purpose: :intake)
  rescue ActiveSupport::MessageVerifier::InvalidSignature
    nil
  end

  def render_invalid
    render inertia: "PublicIntake", props: { token: nil, invalid: true }
  end
end
