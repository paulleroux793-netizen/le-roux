# Phase 8 (P8.1) — Medical (Discovery) rate per procedure code, for the Medical/Self split on
# documents. Practice fee (default_fee_cents) = what the practice charges (latest tx value);
# medical_fee_cents = the medical-aid (Discovery) rate; Self = practice − medical. ADDITIVE.
class AddMedicalFeeToProcedureCodes < ActiveRecord::Migration[8.1]
  def change
    add_column :procedure_codes, :medical_fee_cents, :integer
  end
end
