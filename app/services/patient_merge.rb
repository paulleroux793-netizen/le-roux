# Merge a self-registered placeholder INTO an existing (target) patient — reception's audited,
# deliberate action (the public intake link never auto-merges; see IntakesController). Moves the
# placeholder's submissions / medical history / appointments / conversations onto the target,
# fills only the GAPS on the target (never overwrites verified data, respects unique indexes),
# records consent (the intake form is signed), ensures the target has an account, then deletes
# the placeholder. All in one transaction.
class PatientMerge
  def self.call(placeholder:, target:)
    raise ArgumentError, "cannot merge a patient into itself" if placeholder.id == target.id

    ActiveRecord::Base.transaction do
      # Re-home the placeholder's records onto the target.
      placeholder.form_submissions.update_all(patient_id: target.id) if placeholder.respond_to?(:form_submissions)
      placeholder.appointments.update_all(patient_id: target.id)     if placeholder.respond_to?(:appointments)
      placeholder.conversations.update_all(patient_id: target.id)    if placeholder.respond_to?(:conversations)
      if target.medical_history.nil? && placeholder.medical_history
        placeholder.medical_history.update!(patient_id: target.id)
      end

      # Fill gaps on the target only (verified data wins; unique columns guarded).
      target.date_of_birth ||= placeholder.date_of_birth
      target.email = placeholder.email if target.email.blank? && placeholder.email.present?
      if target.id_number.blank? && placeholder.id_number.present? &&
         !Patient.where.not(id: target.id).exists?(id_number: placeholder.id_number)
        target.id_number = placeholder.id_number
      end
      if target.phone.blank? && placeholder.phone.present? &&
         !Patient.where.not(id: target.id).exists?(phone: placeholder.phone)
        target.phone = placeholder.phone
      end
      if target.consent_to_ai_processing_at.blank?
        target.consent_to_ai_processing_at = Time.current
        target.consent_to_ai_processing_by = "Online intake form (merged)"
      end
      target.save!

      ensure_account!(target)
      placeholder.reload.destroy!
    end
    target
  end

  # Give a patient a billing account (surname-initial scheme) if they don't have one yet.
  def self.ensure_account!(patient)
    return if patient.account_patients.exists?
    ba = BillingAccount.create!(account_code: BillingAccount.next_account_code(patient.last_name),
                                billing_name: patient.full_name, head_patient_id: patient.id)
    AccountPatient.create!(billing_account: ba, patient: patient, relationship: "self")
  end
end
