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

  # Submissions that make up the current intake: the pending ones, falling back to
  # the most recent per template (so re-opening a completed link still renders).
  def self.pending_or_recent(patient)
    KEYS.filter_map do |key|
      scope = patient.form_submissions.joins(:form_template).where(form_templates: { key: key })
      scope.where(status: %w[sent opened]).order(:created_at).last || scope.order(:created_at).last
    end
  end

  def initialize(patient, answers)
    @patient = patient
    @answers = answers || {}
  end

  def save!
    completed_any = false
    ActiveRecord::Base.transaction do
      completed_any = complete_submissions!
      sync_patient!
      sync_medical_history!
    end

    # AFTER commit, only when something was actually completed this submit (so
    # re-opening a finished link doesn't re-fire): email the pack to the practice AND
    # save it into the "1. Patient Files" OneDrive folder. Both are best-effort —
    # a failure in either must never break the patient's submission.
    if completed_any
      notify_practice!
      file_to_patient_folder!
    end
  end

  private

  attr_reader :patient, :answers

  # Returns true if at least one submission was completed in this run.
  def complete_submissions!
    completed_any = false
    self.class.pending_or_recent(patient).each do |submission|
      data = answers[submission.form_template.key]
      next if data.blank? || submission.status == "completed"

      submission.complete!(data: data)
      completed_any = true
    end
    completed_any
  end

  def notify_practice!
    IntakeMailer.completed(patient).deliver_later
  rescue StandardError => e
    Rails.logger.error("[IntakeProcessor] completion email enqueue failed: #{e.message}")
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
