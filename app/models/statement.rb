# An account statement over a period — the claimable summary the patient submits to their scheme.
class Statement < ApplicationRecord
  belongs_to :billing_account
  validates :statement_number, presence: true, uniqueness: true
  before_validation :assign_number, on: :create
  before_validation { self.generated_at ||= Time.current }

  # Generate a statement for an account over a period (defaults to all-time).
  def self.generate_for(account, period_start: nil, period_end: Date.current)
    invoices = Invoice.where(billing_account_id: account.id, void: false)
    payments = Payment.where(billing_account_id: account.id)
    if period_start
      invoices = invoices.where(invoice_date: period_start..period_end)
      payments = payments.where(received_at: period_start.beginning_of_day..period_end.end_of_day)
    end
    charged = invoices.sum(:total_cents)
    paid = payments.sum(:amount_cents)
    create!(billing_account: account, period_start: period_start, period_end: period_end,
            opening_balance_cents: 0, closing_balance_cents: charged - paid)
  end

  def closing_balance = closing_balance_cents.to_i / 100.0

  private

  def assign_number
    self.statement_number ||= DocumentSequence.next_number("statement", prefix: "STM")
  end
end
