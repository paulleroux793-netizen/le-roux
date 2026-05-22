# Phase 2 (P2.1) — Clinical core: Course of Treatment, treatment items, clinical notes, tooth chart.
# ADDITIVE ONLY. New tables; FKs reference existing patients + the Phase 1 tables.
class CreateClinicalCore < ActiveRecord::Migration[8.1]
  def change
    # The episode of care — the bridge between clinical charting and billing.
    create_table :courses_of_treatment do |t|
      t.bigint  :patient_id, null: false
      t.bigint  :billing_account_id           # who pays (nullable until linked)
      t.bigint  :scheme_membership_id          # reference only (self-claim)
      t.string  :description                    # e.g. "Upper-left quadrant rehabilitation"
      t.string  :setting, null: false, default: "in_chair"  # in_chair / hospital_chair / hospital_theatre / sedation
      t.string  :status, null: false, default: "planned"    # planned / active / completed / closed
      t.string  :authorisation_number          # if patient pre-authorised with their scheme
      t.date    :start_date
      t.date    :end_date
      t.text    :notes
      t.timestamps
      t.index :patient_id
      t.index :billing_account_id
      t.index :status
      t.index :setting
    end

    # One planned/performed procedure within a course of treatment.
    create_table :treatment_items do |t|
      t.bigint  :course_of_treatment_id, null: false
      t.bigint  :procedure_code_id, null: false
      t.string  :provider_name                  # treating practitioner (string until a users table exists)
      t.string  :tooth_number                   # FDI two-digit notation (e.g. "16")
      t.string  :surface                         # e.g. "MOD"
      t.date    :planned_date
      t.date    :completed_date
      t.string  :status, null: false, default: "planned"  # planned / completed / failed / voided
      t.integer :fee_cents                       # snapshot of the fee at charting time
      t.string  :vat_treatment, null: false, default: "zero_rated"
      t.text    :notes
      t.timestamps
      t.index :course_of_treatment_id
      t.index :procedure_code_id
      t.index :status
    end

    # Clinical notes (SOAP). Append-only: once signed they lock; corrections add a new note.
    create_table :clinical_notes do |t|
      t.bigint  :patient_id, null: false
      t.bigint  :course_of_treatment_id
      t.text    :subjective
      t.text    :objective
      t.text    :assessment
      t.text    :plan
      t.string  :signed_by
      t.datetime :signed_at
      t.boolean :locked, null: false, default: false
      t.bigint  :supersedes_id                   # points at the note this one corrects (audit chain)
      t.timestamps
      t.index :patient_id
      t.index :course_of_treatment_id
      t.index :locked
    end

    # Per-tooth chart state (odontogram). Each entry is a dated observation/condition.
    create_table :tooth_chart_entries do |t|
      t.bigint  :patient_id, null: false
      t.string  :tooth_number, null: false       # FDI
      t.string  :surface
      t.string  :condition, null: false          # caries / filling / crown / missing / root_canal / implant / healthy ...
      t.bigint  :course_of_treatment_id
      t.bigint  :treatment_item_id
      t.datetime :noted_at, null: false
      t.string :noted_by
      t.timestamps
      t.index [ :patient_id, :tooth_number ]
      t.index :course_of_treatment_id
    end

    add_foreign_key :courses_of_treatment, :patients
    add_foreign_key :courses_of_treatment, :billing_accounts
    add_foreign_key :courses_of_treatment, :scheme_memberships
    add_foreign_key :treatment_items, :courses_of_treatment, column: :course_of_treatment_id
    add_foreign_key :treatment_items, :procedure_codes
    add_foreign_key :clinical_notes, :patients
    add_foreign_key :clinical_notes, :courses_of_treatment, column: :course_of_treatment_id
    add_foreign_key :clinical_notes, :clinical_notes, column: :supersedes_id
    add_foreign_key :tooth_chart_entries, :patients
    add_foreign_key :tooth_chart_entries, :courses_of_treatment, column: :course_of_treatment_id
    add_foreign_key :tooth_chart_entries, :treatment_items
  end
end
