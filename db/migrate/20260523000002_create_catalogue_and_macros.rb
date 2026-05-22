# Phase 1 (P1.2) — Procedure-code catalogue, fee schedules, and treatment macros.
#
# ADDITIVE ONLY. New tables. Grounded in the practice's real data:
#   - procedure_codes  : SADA tariff codes (8101, 8201, 8341, modifiers 8025/8099/9099 ...)
#   - treatment_macros : imported from "Dental Macro's.xlsx" (AccessCode -> bundle of codes)
#   - fee_schedules    : price lists (PRIVATE <year>; scheme tariffs are reference-only)
class CreateCatalogueAndMacros < ActiveRecord::Migration[8.1]
  def change
    # The billable-procedure catalogue (SADA/practice tariff codes).
    create_table :procedure_codes do |t|
      t.string  :code, null: false                 # SADA/internal tariff code, e.g. "8101"
      t.string  :description, null: false
      t.string  :category                            # diagnostic / restorative / surgical / preventive / cosmetic / lab / material
      t.string  :vat_treatment, null: false, default: "zero_rated"  # zero_rated (medical) | standard (cosmetic 15%)
      t.boolean :tooth_specific, null: false, default: false
      t.integer :default_fee_cents                   # practice fee in cents (ZAR)
      t.boolean :requires_authorisation, null: false, default: false
      t.integer :max_per_year                        # frequency limit (nil = none)
      t.integer :age_min                             # age restriction lower bound (nil = none)
      t.integer :age_max
      t.boolean :lab_fee_applicable, null: false, default: false      # "PLUS L"
      t.boolean :material_fee_applicable, null: false, default: false # "PLUS M"
      t.boolean :active, null: false, default: true
      t.timestamps
      t.index :code, unique: true
      t.index :category
      t.index :active
    end

    # Price lists. For this non-claiming practice the main one is "PRIVATE <year>";
    # scheme schedules are kept only as reference for the self-claim statement.
    create_table :fee_schedules do |t|
      t.string  :name, null: false                  # e.g. "PRIVATE 2026"
      t.integer :year
      t.bigint  :medical_scheme_id                   # nullable; set for scheme reference lists
      t.string  :plan_option
      t.boolean :active, null: false, default: true
      t.timestamps
      t.index :medical_scheme_id
      t.index [ :name, :year ]
    end

    create_table :fee_schedule_items do |t|
      t.bigint  :fee_schedule_id, null: false
      t.bigint  :procedure_code_id, null: false
      t.integer :practice_fee_cents, null: false, default: 0
      t.integer :allowed_amount_cents                # scheme reference amount (nullable)
      t.timestamps
      t.index [ :fee_schedule_id, :procedure_code_id ], unique: true, name: "idx_fee_schedule_items_unique"
      t.index :procedure_code_id
    end

    # Treatment macros — a named bundle that expands to many procedure lines.
    # Mirrors "Dental Macro's.xlsx": AccessCode, Name, Laboratory, + line items w/ quantity.
    create_table :treatment_macros do |t|
      t.string  :access_code, null: false           # e.g. "BRIDGE 3"
      t.string  :name, null: false                   # e.g. "3 UNIT BRIDGE"
      t.boolean :laboratory, null: false, default: false
      t.text    :notes
      t.boolean :active, null: false, default: true
      t.timestamps
      t.index :access_code, unique: true
    end

    create_table :treatment_macro_items do |t|
      t.bigint  :treatment_macro_id, null: false
      t.bigint  :procedure_code_id                   # nullable: resolved by tariff_code if catalogue not yet seeded
      t.string  :tariff_code                         # raw code from the xlsx, e.g. "8447"
      t.integer :quantity, null: false, default: 1
      t.integer :position, null: false, default: 0
      t.text    :more_info
      t.timestamps
      t.index :treatment_macro_id
      t.index :procedure_code_id
    end

    add_foreign_key :fee_schedules, :medical_schemes
    add_foreign_key :fee_schedule_items, :fee_schedules
    add_foreign_key :fee_schedule_items, :procedure_codes
    add_foreign_key :treatment_macro_items, :treatment_macros
    add_foreign_key :treatment_macro_items, :procedure_codes
  end
end
