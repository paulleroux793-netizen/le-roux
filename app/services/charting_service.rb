# ChartingService — the bridge between the clickable odontogram and the
# patient's open Course of Treatment. P9.3.
#
# Workflow:
#   1. Receptionist (or dentist) clicks a tooth on the odontogram
#   2. Picks a condition from the chip palette (caries, crown, …)
#   3. Optionally picks a procedure code (defaults to the suggestion below)
#   4. We record a ToothChartEntry AND, if a code was picked, a planned
#      TreatmentItem on the patient's open COT — auto-creating the COT if
#      none exists. Same transaction; both succeed or neither.
#
# The condition→code map is intentionally tiny and conservative. It
# proposes the MOST COMMON SADA procedure for each chart condition so the
# clinician usually just confirms. They can always override in the modal.
class ChartingService
  # FDI tooth condition → preferred SADA procedure tariff code.
  # Deliberately omits "healthy" and "missing" — those record a chart
  # observation only, no procedure.
  CONDITION_PROCEDURE = {
    "caries"             => "8367", # Resin - one surface, posterior
    "filling"            => "8367", # (same — "filling" reads as "needs a filling")
    "crown"              => "8409", # Crown - porcelain/ceramic
    "bridge"             => "8523", # Fabrication of pontic — pragmatic stand-in
    "root_canal"         => "8132", # Pulp removal (pulpectomy) — first step of RCT
    "extraction_planned" => "8201", # Extraction - tooth or roots (first per quadrant)
    "fracture"           => "8131", # Emergency dental treatment
    "implant"            => "9183", # Surgical placement of endosteal implant
  }.freeze

  # Returns the suggested ProcedureCode (or nil) for a condition.
  # Always queries `active` only — never proposes a retired code.
  def self.suggested_code(condition)
    code = CONDITION_PROCEDURE[condition.to_s]
    return nil unless code
    ProcedureCode.active.find_by(code: code)
  end

  # Pre-baked map shipped to the React modal so it can render the
  # suggestion without a follow-up fetch. Shape:
  #   { "caries" => { id: 42, code: "8367", description: "...", fee: 450.0 } }
  def self.suggestions_for_props
    CONDITION_PROCEDURE.keys.each_with_object({}) do |condition, hash|
      pc = suggested_code(condition)
      next unless pc
      hash[condition] = {
        id:          pc.id,
        code:        pc.code,
        description: pc.description,
        fee:         pc.default_fee,
        medical:     pc.medical_fee,
      }
    end
  end

  # The actual write. Returns [cot, treatment_item|nil].
  # Raises ActiveRecord::RecordInvalid on validation failure — caller
  # decides whether to swallow or surface.
  def self.add_from_chart(patient:, tooth_number:, condition:, procedure_code_id: nil)
    tooth_number = tooth_number.to_i
    raise ArgumentError, "invalid condition" unless ToothChartEntry::CONDITIONS.include?(condition.to_s)
    raise ArgumentError, "invalid tooth number" unless tooth_number.between?(11, 48)

    cot = CourseOfTreatment.where(patient_id: patient.id).open.order(created_at: :desc).first
    cot ||= CourseOfTreatment.create!(
      patient: patient, setting: "in_chair", status: "active",
      description: "Chart-driven plan — #{Date.current.iso8601}"
    )

    treatment_item = nil
    ActiveRecord::Base.transaction do
      ToothChartEntry.create!(
        patient: patient, course_of_treatment: cot,
        tooth_number: tooth_number, condition: condition.to_s,
        noted_at: Time.current
      )

      if procedure_code_id.present?
        pc = ProcedureCode.find(procedure_code_id)
        treatment_item = cot.treatment_items.create!(
          procedure_code: pc, tooth_number: tooth_number,
          status: "planned",
          icd10_code: Icd10Code::CONDITION_DEFAULT[condition.to_s]
        )
      end
    end

    [ cot, treatment_item ]
  end
end
