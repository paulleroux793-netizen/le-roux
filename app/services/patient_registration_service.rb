class PatientRegistrationService
  Result = Struct.new(
    :patient,
    :created,
    :upgraded_placeholder,
    :existing_patient,
    keyword_init: true
  ) do
    def success?
      patient.errors.empty?
    end

    def created?
      created
    end

    def upgraded_placeholder?
      upgraded_placeholder
    end
  end

  def initialize(attributes:)
    @attributes = normalize_attributes(attributes)
  end

  def call
    existing_patient = Patient.includes(:medical_history).find_by(phone: @attributes[:phone])

    return persist(Patient.new(@attributes), created: true) unless existing_patient

    if existing_patient.auto_created_placeholder_profile?
      existing_patient.assign_attributes(@attributes)
      return persist(existing_patient, upgraded_placeholder: true)
    end

    duplicate_error(existing_patient)
  end

  private

  def persist(patient, created: false, upgraded_placeholder: false)
    patient.save

    Result.new(
      patient: patient,
      created: created && patient.persisted?,
      upgraded_placeholder: upgraded_placeholder && patient.persisted?,
      existing_patient: patient
    )
  end

  def duplicate_error(existing_patient)
    patient = Patient.new(@attributes)
    patient.valid?
    patient.errors.delete(:phone)
    patient.errors.add(:phone, "already belongs to an existing patient record")

    Result.new(
      patient: patient,
      created: false,
      upgraded_placeholder: false,
      existing_patient: existing_patient
    )
  end

  def normalize_attributes(attributes)
    attrs = attributes.to_h.deep_symbolize_keys
    attrs[:phone] = normalize_phone(attrs[:phone])

    medical_history = attrs[:medical_history_attributes]
    return attrs unless medical_history.is_a?(Hash)

    cleaned = medical_history.deep_symbolize_keys
    cleaned = cleaned.compact_blank
    if cleaned.except(:id).empty?
      attrs.delete(:medical_history_attributes)
      return attrs
    end

    attrs[:medical_history_attributes] = cleaned
    attrs
  end

  def normalize_phone(phone)
    Patient.canonical_phone(phone)
  end
end
