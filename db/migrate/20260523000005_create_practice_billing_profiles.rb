# Phase 3 (P3.3) — Billing/registration identity for compliant invoices & statements.
# Separate ADDITIVE table so the live practice_settings table is untouched. Singleton-ish.
class CreatePracticeBillingProfiles < ActiveRecord::Migration[8.1]
  def change
    create_table :practice_billing_profiles do |t|
      t.string :practice_name, null: false, default: "Dr Chalita le Roux Inc"
      t.string :hpcsa_number               # practice HPCSA, e.g. "DP 0118702"
      t.string :bhf_practice_number        # BHF practice number (placeholder until Paul provides — UNCERTAINTIES #3)
      t.string :company_reg
      t.boolean :vat_registered, null: false, default: false  # UNCERTAINTIES #17
      t.string :vat_number
      t.string :practitioner_name
      t.string :practitioner_hpcsa_number
      t.string :practitioner_bhf_number
      t.string :phone
      t.string :email
      t.string :address_line1
      t.string :address_line2
      t.string :city
      t.string :postal_code
      t.string :bank_name
      t.string :bank_account_name
      t.string :bank_account_number
      t.string :bank_branch_code
      t.timestamps
    end
  end
end
