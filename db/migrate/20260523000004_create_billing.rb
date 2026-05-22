# Phase 3 (P3.1) — Money: estimates, invoices, payments, statements + atomic doc numbering.
# ADDITIVE ONLY. Patient-pay model (no medical-aid submission). Money stored in integer cents (ZAR).
class CreateBilling < ActiveRecord::Migration[8.1]
  def change
    # Atomic, gap-free document numbering (tax-compliant sequential invoice numbers).
    create_table :document_sequences do |t|
      t.string  :key, null: false           # e.g. "invoice", "estimate", "statement"
      t.integer :current_value, null: false, default: 0
      t.timestamps
      t.index :key, unique: true
    end

    create_table :estimates do |t|
      t.bigint  :patient_id, null: false
      t.bigint  :billing_account_id
      t.bigint  :course_of_treatment_id
      t.string  :estimate_number, null: false
      t.string  :status, null: false, default: "draft"  # draft / sent / accepted / rejected / expired
      t.integer :subtotal_cents, null: false, default: 0
      t.integer :vat_cents, null: false, default: 0
      t.integer :total_cents, null: false, default: 0
      t.date    :valid_until
      t.datetime :sent_at
      t.datetime :accepted_at
      t.text    :notes
      t.timestamps
      t.index :estimate_number, unique: true
      t.index :patient_id
      t.index :course_of_treatment_id
      t.index :status
    end

    create_table :estimate_lines do |t|
      t.bigint  :estimate_id, null: false
      t.bigint  :procedure_code_id
      t.bigint  :treatment_item_id
      t.string  :code
      t.string  :description
      t.string  :tooth_number
      t.integer :quantity, null: false, default: 1
      t.integer :unit_fee_cents, null: false, default: 0
      t.string  :vat_treatment, null: false, default: "zero_rated"
      t.integer :vat_cents, null: false, default: 0
      t.integer :line_total_cents, null: false, default: 0
      t.timestamps
      t.index :estimate_id
    end

    create_table :invoices do |t|
      t.bigint  :patient_id, null: false
      t.bigint  :billing_account_id
      t.bigint  :course_of_treatment_id
      t.string  :invoice_number, null: false           # sequential, gap-free
      t.date    :invoice_date, null: false
      t.string  :status, null: false, default: "open"  # open / part_paid / paid / written_off / void
      t.boolean :void, null: false, default: false
      t.integer :subtotal_cents, null: false, default: 0
      t.integer :vat_cents, null: false, default: 0
      t.integer :total_cents, null: false, default: 0
      t.integer :paid_cents, null: false, default: 0
      t.text    :notes
      t.timestamps
      t.index :invoice_number, unique: true
      t.index :patient_id
      t.index :billing_account_id
      t.index :status
    end

    create_table :invoice_lines do |t|
      t.bigint  :invoice_id, null: false
      t.bigint  :procedure_code_id
      t.bigint  :treatment_item_id
      t.string  :code
      t.string  :description
      t.string  :tooth_number
      t.integer :quantity, null: false, default: 1
      t.integer :unit_fee_cents, null: false, default: 0
      t.string  :vat_treatment, null: false, default: "zero_rated"
      t.integer :vat_cents, null: false, default: 0
      t.integer :line_total_cents, null: false, default: 0
      t.timestamps
      t.index :invoice_id
    end

    create_table :payments do |t|
      t.bigint  :billing_account_id
      t.bigint  :patient_id
      t.bigint  :invoice_id
      t.string  :method, null: false, default: "card"  # card / cash / eft
      t.integer :amount_cents, null: false
      t.boolean :is_deposit, null: false, default: false
      t.string  :reference
      t.datetime :received_at, null: false
      t.text    :notes
      t.timestamps
      t.index :billing_account_id
      t.index :invoice_id
      t.index :received_at
    end

    create_table :statements do |t|
      t.bigint  :billing_account_id, null: false
      t.string  :statement_number, null: false
      t.date    :period_start
      t.date    :period_end
      t.datetime :generated_at, null: false
      t.integer :opening_balance_cents, null: false, default: 0
      t.integer :closing_balance_cents, null: false, default: 0
      t.timestamps
      t.index :statement_number, unique: true
      t.index :billing_account_id
    end

    add_foreign_key :estimates, :patients
    add_foreign_key :estimates, :billing_accounts
    add_foreign_key :estimates, :courses_of_treatment, column: :course_of_treatment_id
    add_foreign_key :estimate_lines, :estimates
    add_foreign_key :invoices, :patients
    add_foreign_key :invoices, :billing_accounts
    add_foreign_key :invoices, :courses_of_treatment, column: :course_of_treatment_id
    add_foreign_key :invoice_lines, :invoices
    add_foreign_key :payments, :billing_accounts
    add_foreign_key :payments, :invoices
    add_foreign_key :statements, :billing_accounts
  end
end
