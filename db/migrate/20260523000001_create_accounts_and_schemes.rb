# Phase 1 (P1.1) — Practice-management foundation: billing accounts + medical schemes.
#
# ADDITIVE ONLY. Creates new tables and links to the existing `patients` table via
# join tables (account_patients, scheme_membership_patients) so the live `patients`
# table is NOT modified. Nothing here touches bookings, calendar, or WhatsApp.
class CreateAccountsAndSchemes < ActiveRecord::Migration[8.1]
  def change
    # The unit that OWES money to the practice (a person or a family).
    create_table :billing_accounts do |t|
      t.string  :account_code               # e.g. "M0174" (matches existing GoodX account no.)
      t.string  :billing_name, null: false   # who the statement is addressed to
      t.string  :email
      t.string  :phone
      t.string  :address_line1
      t.string  :address_line2
      t.string  :city
      t.string  :postal_code
      t.bigint  :head_patient_id             # FK -> patients (the guarantor); nullable
      t.text    :notes
      t.timestamps
      t.index :account_code, unique: true, where: "account_code IS NOT NULL"
      t.index :head_patient_id
      t.index :billing_name
    end

    # Link patients to a billing account without altering the patients table.
    create_table :account_patients do |t|
      t.bigint  :billing_account_id, null: false
      t.bigint  :patient_id, null: false
      t.string  :relationship, null: false, default: "self"  # self / head / dependant / guardian
      t.timestamps
      t.index [ :billing_account_id, :patient_id ], unique: true, name: "idx_account_patients_unique"
      t.index :patient_id
    end

    # A medical aid scheme (reference data — we NEVER submit to it; printed on statements
    # so the patient can self-claim).
    create_table :medical_schemes do |t|
      t.string :name, null: false
      t.string :scheme_code
      t.string :administrator
      t.boolean :active, null: false, default: true
      t.timestamps
      t.index :scheme_code, unique: true, where: "scheme_code IS NOT NULL"
      t.index :name
    end

    # A membership contract: a main member on a scheme/plan.
    create_table :scheme_memberships do |t|
      t.bigint  :medical_scheme_id, null: false
      t.bigint  :main_member_patient_id        # FK -> patients; nullable (main member may not be a patient)
      t.string  :main_member_name              # as registered with the scheme (char-for-char)
      t.string  :member_number, null: false
      t.string  :plan_option
      t.date    :effective_from
      t.date    :effective_to
      t.timestamps
      t.index :medical_scheme_id
      t.index :main_member_patient_id
      t.index :member_number
    end

    # Link patients (dependants) to a membership with their dependant code.
    create_table :scheme_membership_patients do |t|
      t.bigint  :scheme_membership_id, null: false
      t.bigint  :patient_id, null: false
      t.string  :dependant_code               # e.g. "00" main, "01" spouse, "02"+ children
      t.string  :role, null: false, default: "dependant"  # main_member / dependant
      t.timestamps
      t.index [ :scheme_membership_id, :patient_id ], unique: true, name: "idx_scheme_membership_patients_unique"
      t.index :patient_id
    end

    # FKs to existing patients (safe — adds constraints referencing patients, no column changes).
    add_foreign_key :billing_accounts, :patients, column: :head_patient_id
    add_foreign_key :account_patients, :billing_accounts
    add_foreign_key :account_patients, :patients
    add_foreign_key :scheme_memberships, :medical_schemes
    add_foreign_key :scheme_memberships, :patients, column: :main_member_patient_id
    add_foreign_key :scheme_membership_patients, :scheme_memberships
    add_foreign_key :scheme_membership_patients, :patients
  end
end
