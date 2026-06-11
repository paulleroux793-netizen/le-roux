class AddSettlementCreditsAndPaymentKinds < ActiveRecord::Migration[8.1]
  # Settlement maturity: account-level CREDIT (overpayments + deposits land here and can
  # be applied to other invoices), and a payment KIND so the ledger can tell apart real
  # payments, deposits, credit applications, refunds and reversals. All additive with safe
  # defaults — existing payments become kind="payment" (unchanged behaviour) and every
  # account starts with 0 credit.
  def change
    add_column :billing_accounts, :credit_cents, :integer, null: false, default: 0

    add_column :payments, :kind,        :string, null: false, default: "payment"
    add_column :payments, :reversed_at, :datetime
    add_column :payments, :reason,      :string
    add_index  :payments, :kind
  end
end
