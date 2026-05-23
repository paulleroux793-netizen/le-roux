# Phase 9 — ICD-10 diagnosis codes (required on every claimable invoice line in SA).
# ADDITIVE ONLY. Reference table + a nullable string column on each line/item table so the
# dentist can attach a diagnosis to a procedure (matches the practice's existing estimate layout
# that shows "ICD-10: K02.8" per line).
class CreateIcd10CodesAndLinkToLines < ActiveRecord::Migration[8.1]
  def change
    create_table :icd10_codes do |t|
      t.string  :code, null: false           # e.g. "K02.9"
      t.string  :description, null: false    # e.g. "Dental caries, unspecified"
      t.string  :category                     # e.g. "K02 Dental caries" / "K04 Pulpal"
      t.boolean :active, null: false, default: true
      t.timestamps
      t.index :code, unique: true
      t.index :category
    end

    add_column :invoice_lines,    :icd10_code, :string
    add_column :estimate_lines,   :icd10_code, :string
    add_column :treatment_items,  :icd10_code, :string
  end
end
