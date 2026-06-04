class PatientMedicalHistory < ApplicationRecord
  # 1:1 with Patient. See CreatePatientMedicalHistories migration for
  # the rationale for extracting this into its own table.
  belongs_to :patient

  # POPIA s19 — health data is special personal information; encrypt the free-text
  # clinical fields and the emergency/insurance identifiers at rest. blood_type and
  # insurance_provider (scheme name) stay plaintext: low-sensitivity and used for
  # filtering/display. Existing rows are re-encrypted by `bin/rails phi:encrypt`.
  encrypts :allergies
  encrypts :chronic_conditions
  encrypts :current_medications
  encrypts :dental_notes
  encrypts :emergency_contact_name
  encrypts :emergency_contact_phone
  encrypts :insurance_policy_number

  # Whitelist blood types so the form renders a fixed dropdown and
  # bad data can't sneak in via the API. `nil`/blank is allowed —
  # a patient may not know their blood type.
  BLOOD_TYPES = %w[A+ A- B+ B- AB+ AB- O+ O-].freeze

  validates :blood_type, inclusion: { in: BLOOD_TYPES }, allow_blank: true
  validates :emergency_contact_phone,
            format: { with: /\A\+?\d{10,15}\z/, message: "must be a valid phone number" },
            allow_blank: true

  # True if the patient has provided any medical information at all —
  # used by PatientShow to decide whether to render the panel empty
  # state or the populated view.
  def any_data?
    [
      allergies, chronic_conditions, current_medications, blood_type,
      emergency_contact_name, emergency_contact_phone,
      insurance_provider, insurance_policy_number,
      dental_notes, last_dental_visit
    ].any?(&:present?)
  end
end
