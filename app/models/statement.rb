# An account statement over a period — the claimable summary the patient submits to their scheme.
class Statement < ApplicationRecord
  belongs_to :billing_account
  validates :statement_number, presence: true, uniqueness: true
  before_validation :assign_number, on: :create
  before_validation { self.generated_at ||= Time.current }

  # Generate a statement for an account over a period (defaults to all-time). Carries a
  # brought-forward OPENING balance so a period statement shows true cumulative debt, not
  # just that period's activity. Excludes voided/written-off invoices and reversed payments.
  def self.generate_for(account, period_start: nil, period_end: Date.current)
    invoices = Invoice.where(billing_account_id: account.id, void: false).where.not(status: "written_off")
    payments = Payment.where(billing_account_id: account.id).inward # active, real money in

    opening = 0
    if period_start
      opening = invoices.where("invoice_date < ?", period_start).sum(:total_cents) -
                payments.where("received_at < ?", period_start.beginning_of_day).sum(:amount_cents)
      invoices = invoices.where(invoice_date: period_start..period_end)
      payments = payments.where(received_at: period_start.beginning_of_day..period_end.end_of_day)
    end

    charged = invoices.sum(:total_cents)
    paid    = payments.sum(:amount_cents)
    create!(billing_account: account, period_start: period_start, period_end: period_end,
            opening_balance_cents: opening, closing_balance_cents: opening + charged - paid)
  end

  def closing_balance = closing_balance_cents.to_i / 100.0

  private

  def assign_number
    self.statement_number ||= DocumentSequence.next_number("statement", prefix: "STM")
  end
end
