# Applies a completed intake to the patient's record.
#
# `answers` is { template_key => { field_key => value } }. For each template we
# complete the patient's pending FormSubmission (which files a Document via
# FormSubmission#complete!), storing the FULL answer set as the source of truth that
# IntakePdf renders from. We ALSO denormalise the convenient fields onto the Patient
# and PatientMedicalHistory so the dashboard shows them without parsing form data.
#
# Faithful-but-safe: we never blank an existing value with an empty answer, and the
# raw form data is always preserved even for fields that have no dedicated column.
class IntakeProcessor
  KEYS = %w[patient_details health_questionnaire consent_treatment].freeze
  # Stamped into a self-registration's `notes` once its completion email is confirmed
  # delivered. The hourly reconciliation re-sends any self-registration that LACKS this,
  # so a silently-failed inline send can never lose a form. (Stable per-patient key — far
  # more reliable than matching by name, which reception edits during review.)
  EMAILED_MARKER = "[emailed]".freeze

  # Submissions that make up the current intake: the pending ones, falling back to
  # the most recent per template (so re-opening a completed link still renders).
  def self.pending_or_recent(patient)
    KEYS.filter_map do |key|
      scope = patient.form_submissions.joins(:form_template).where(form_templates: { key: key })
      scope.where(status: %w[sent opened]).order(:created_at).last || scope.order(:created_at).last
    end
  end

  def initialize(patient, answers, self_registration: false)
    @patient = patient
    @answers = answers || {}
    # A public self-registration (the shared /intake/new link) only CAPTURES the form data;
    # it must never write the patient's identity/medical columns, because the record is an
    # unverified placeholder that reception still has to confirm + merge. The token (known
    # patient) flow leaves this false and syncs as before.
    @self_registration = self_registration
  end

  def save!
    completed_any = false
    ActiveRecord::Base.transaction do
      completed_any = complete_submissions!
      unless @self_registration
        sync_patient!
        sync_medical_history!
      end
    end

    # AFTER commit, only when something was actually completed this submit (so
    # re-opening a finished link doesn't re-fire): email the pack to the practice AND
    # save it into the "1. Patient Files" OneDrive folder. Both are best-effort —
    # a failure in either must never break the patient's submission.
    if completed_any
      notify_practice!
      notify_in_app!
      file_to_patient_folder!
    end
  end

  private

  attr_reader :patient, :answers

  # Submit completes the WHOLE intake, so complete every still-pending submission —
  # even one a patient legitimately left blank (e.g. no medical history). Skipping
  # empty sections used to leave them "opened" forever, so `completed` never went
  # true and the thank-you screen never showed. Returns true if anything completed.
  def complete_submissions!
    completed_any = false
    self.class.pending_or_recent(patient).each do |submission|
      next if submission.status == "completed"

      submission.complete!(data: answers[submission.form_template.key] || {})
      completed_any = true
    end
    completed_any
  end

  def notify_practice!
    # Send INLINE (deliver_now), not deliver_later: the completion email is the practice's
    # real-time signal that a patient finished, and a background job can be delayed or lost
    # (the queue worker runs in Puma, so a restart can drop a just-enqueued job). Bounded by
    # the SMTP open/read timeouts in production.rb; still best-effort — a send failure is
    # logged and never breaks the patient's submission, and the hourly reconciliation will
    # re-send it (it stays unmarked below).
    IntakeMailer.completed(patient).deliver_now
    mark_emailed! if @self_registration
  rescue StandardError => e
    Rails.logger.error("[IntakeProcessor] completion email failed: #{e.message}")
  end

  # In-app notification (the bell) so reception sees a completed form immediately and never
  # misses it — the email can be buried, and a form submission is not a WhatsApp message.
  def notify_in_app!
    NotificationService.intake_completed(patient)
  rescue StandardError => e
    Rails.logger.error("[IntakeProcessor] in-app notification failed: #{e.message}")
  end

  # Stamp EMAILED_MARKER into notes once the email is confirmed sent (reached only if
  # deliver_now didn't raise). update_column skips validations/callbacks. Best-effort: a
  # failure here just means the reconciliation harmlessly re-sends once.
  def mark_emailed!
    return if patient.notes.to_s.include?(EMAILED_MARKER)
    patient.update_column(:notes, [ patient.notes.presence, EMAILED_MARKER ].compact.join(" "))
  rescue StandardError => e
    Rails.logger.error("[IntakeProcessor] mark_emailed failed: #{e.message}")
  end

  def file_to_patient_folder!
    IntakeFiler.call(patient)
  rescue StandardError => e
    Rails.logger.error("[IntakeProcessor] patient-folder save failed: #{e.message}")
  end

  # Map the patient_details answers onto the Patient (present values only).
  def sync_patient!
    d = answers["patient_details"] or return
    attrs = {
      first_name:    d["first_name"],
      last_name:     d["last_name"],
      date_of_birth: d["date_of_birth"],
      id_number:     d["id_number"]
    }.compact_blank
    # Only set phone if the patient doesn't already have one (live WhatsApp flows own it).
    attrs[:phone] = d["contact_number"] if patient.phone.blank? && d["contact_number"].present?
    # Capture the patient's email — but only if it's a valid address, so a typo can't
    # fail the whole submission (the raw answer is preserved in the form data regardless).
    attrs[:email] = d["email"] if d["email"].to_s.match?(URI::MailTo::EMAIL_REGEXP)
    patient.update!(attrs) if attrs.any?
  end

  # Roll the health questionnaire + emergency contact + medical aid into the 1:1
  # PatientMedicalHistory record for at-a-glance display on the patient profile.
  def sync_medical_history!
    history = patient.medical_history_or_build
    pd = answers["patient_details"] || {}
    hq = answers["health_questionnaire"] || {}

    history.emergency_contact_name  = pd["emergency_contact_name"]  if pd["emergency_contact_name"].present?
    history.emergency_contact_phone = pd["emergency_contact_phone"] if pd["emergency_contact_phone"].present?
    history.insurance_provider      = pd["scheme_name"]   if pd["scheme_name"].present?
    history.insurance_policy_number = pd["member_number"] if pd["member_number"].present?

    history.allergies           = hq["allergies"]        if hq["allergies"].present?
    history.chronic_conditions  = summarise_yes(hq, ILLNESS_LABELS)   if hq.present?
    history.current_medications = summarise_yes(hq, MEDICATION_LABELS) if hq.present?

    history.save! if history.changed?
  end

  # Build a human-readable "Diabetes, Asthma…" string from the yes/no answers.
  def summarise_yes(answers, labels)
    picked = labels.select { |key, _| truthy?(answers[key]) }.map { |_, label| label }
    picked.join(", ").presence
  end

  def truthy?(value)
    [true, "true", "1", "yes", "on"].include?(value)
  end

  # Mirror the labels used in db/seeds/intake_forms.rb so the summaries read well.
  ILLNESS_LABELS = {
    "bp" => "High/low blood pressure", "angina" => "Angina",
    "rheumatic_fever" => "Rheumatic/scarlet fever", "congenital_heart" => "Congenital heart disease",
    "respiratory" => "Asthma/bronchitis/emphysema/TB", "liver" => "Liver disease",
    "kidney" => "Kidney disease", "diabetes" => "Diabetes", "epilepsy" => "Epilepsy",
    "bleeding" => "Bleeding tendency", "anemia" => "Anemia", "arthritis" => "Arthritis",
    "muscular" => "Muscular disease"
  }.freeze

  MEDICATION_LABELS = {
    "med_cortisone" => "Cortisone/steroids", "med_antidepressants" => "Anti-depressants",
    "med_sedatives" => "Tranquilizers/sedatives", "med_anticoagulants" => "Blood thinners",
    "med_antihypertensives" => "Anti-hypertensives", "med_thyroid" => "Thyroid drugs",
    "med_contraceptives" => "Contraceptives", "med_bisphosphonate" => "Bisphosphonate/bone density"
  }.freeze
end
