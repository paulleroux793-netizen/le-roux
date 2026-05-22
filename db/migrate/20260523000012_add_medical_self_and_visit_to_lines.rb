# Phase 8 (P8.2) — Medical/Self split + Visit grouping on document lines (matches the practice's
# familiar estimate format). ADDITIVE.
#   medical_cents = medical-aid (Discovery) portion; self_cents = line_total − medical (patient pays).
#   visit = which appointment the line belongs to (replaces the confusing "1st/2nd phase").
class AddMedicalSelfAndVisitToLines < ActiveRecord::Migration[8.1]
  def change
    add_column :invoice_lines,  :medical_cents, :integer, null: false, default: 0
    add_column :invoice_lines,  :self_cents,    :integer, null: false, default: 0
    add_column :estimate_lines, :medical_cents, :integer, null: false, default: 0
    add_column :estimate_lines, :self_cents,    :integer, null: false, default: 0
    add_column :estimate_lines, :visit,         :integer, null: false, default: 1
    add_column :treatment_items, :visit,        :integer, null: false, default: 1
  end
end
