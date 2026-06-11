# The unit that owes money to the practice — a single patient or a family.
# The statement (which the patient submits to their own medical aid) is addressed here.
class BillingAccount < ApplicationRecord
  has_many :account_patients, dependent: :destroy
  has_many :patients, through: :account_patients
  belongs_to :head_patient, class_name: "Patient", optional: true
  has_many :invoices, dependent: :nullify
  has_many :payments, dependent: :nullify
  has_many :statements, dependent: :destroy

  validates :billing_name, presence: true
  validates :account_code, uniqueness: true, allow_nil: true

  # Next account code in the practice's surname-initial scheme: the surname's first letter +
  # a 4-digit running number (e.g. the next free "A0043" for an Adams/Anderson account). Matches
  # the imported Elixir accounts. Names that don't start with a letter fall under "Z".
  def self.next_account_code(surname = nil)
    initial = surname.to_s.gsub(/[^A-Za-z]/, "")[0]&.upcase
    initial = "Z" unless initial && initial.match?(/\A[A-Z]\z/)
    last = where("account_code ~ ?", "^#{initial}[0-9]+$")
             .order(Arel.sql("LENGTH(account_code), account_code")).last
    n = last ? last.account_code[1..].to_i : 0
    format("%s%04d", initial, n + 1)
  end

  # ---- Account credit (overpayments + deposits sit here until applied) ----

  def credit = credit_cents.to_i / 100.0

  def add_credit!(cents)
    c = cents.to_i
    increment!(:credit_cents, c) if c.positive?
  end

  # Take up to `cents` off the credit balance; returns the amount actually removed.
  def deduct_credit!(cents)
    take = [ cents.to_i, credit_cents.to_i ].min
    decrement!(:credit_cents, take) if take.positive?
    take
  end

  # Refund available credit back to the patient (money physically leaves the practice).
  # Caps at the credit on hand; records an outward `refund` payment row. Returns cents refunded.
  def refund!(amount_cents, method: "cash", reason: nil)
    take = [ amount_cents.to_i, credit_cents.to_i ].min
    return 0 if take <= 0

    transaction do
      deduct_credit!(take)
      payments.create!(method: (%w[card cash eft].include?(method) ? method : "cash"),
                       kind: "refund", amount_cents: take, reason: reason, patient: head_patient)
    end
    take
  end

  # Sum still owed across this account's open/part-paid invoices.
  def outstanding_cents
    invoices.outstanding.sum("total_cents - paid_cents")
  end

  # Net account position in cents: what's owed minus available credit. Negative = in credit.
  def balance_cents = outstanding_cents - credit_cents.to_i

  # Apply available credit onto one invoice (default: clear its balance). Returns cents applied.
  # Records a `credit_applied` payment row for the trail (no double-charge — see Payment).
  def apply_credit_to(invoice, cents = nil, method: "credit")
    want = cents&.to_i || invoice.outstanding_cents
    amount = [ want, credit_cents.to_i, invoice.outstanding_cents ].min
    return 0 if amount <= 0

    transaction do
      deduct_credit!(amount)
      invoice.apply_credit!(amount)
      payments.create!(invoice: invoice, patient: invoice.patient, method: method,
                       kind: "credit_applied", amount_cents: amount,
                       reason: "Account credit applied to #{invoice.invoice_number}")
    end
    amount
  end

  # Account-level payment: settle outstanding invoices OLDEST-first, any remainder → credit.
  # One inward payment, allocated across the family's open invoices. Returns a summary hash.
  def receive_payment(amount_cents, method: "card", reference: nil)
    remaining = amount_cents.to_i
    allocations = []
    transaction do
      invoices.outstanding.order(:invoice_date, :id).each do |inv|
        break if remaining <= 0

        portion = [ remaining, inv.outstanding_cents ].min
        next if portion <= 0

        payments.create!(invoice: inv, patient: inv.patient, method: method, kind: "payment",
                         amount_cents: portion, reference: reference)
        allocations << { invoice_id: inv.id, applied_cents: portion }
        remaining -= portion
      end
      if remaining.positive?
        # The deposit row's after_create credits the account — don't add_credit! again here.
        payments.create!(method: method, kind: "deposit", is_deposit: true,
                         amount_cents: remaining, reference: reference,
                         patient: head_patient)
      end
    end
    { allocated: allocations, to_credit_cents: [ amount_cents.to_i - allocations.sum { |a| a[:applied_cents] }, 0 ].max }
  end
end
