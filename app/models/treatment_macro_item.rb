# One line within a treatment macro: a tariff code + quantity. `procedure_code` is
# linked once the catalogue is seeded; `tariff_code` holds the raw code from the xlsx
# so import can run before the catalogue is fully populated.
class TreatmentMacroItem < ApplicationRecord
  belongs_to :treatment_macro
  belongs_to :procedure_code, optional: true

  validates :quantity, numericality: { greater_than: 0 }

  # Resolve the procedure_code link from the raw tariff_code once codes exist.
  def resolve_procedure_code!
    return if procedure_code_id.present? || tariff_code.blank?
    pc = ProcedureCode.find_by(code: tariff_code)
    update!(procedure_code: pc) if pc
  end
end
