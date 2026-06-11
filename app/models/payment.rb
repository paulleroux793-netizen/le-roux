# A payment received at the practice (card / cash / EFT), optionally a deposit (e.g. whitening
# R2,000). If linked to an invoice, it updates that invoice's paid status.
class Payment < ApplicationRecord
  METHODS = %w[card cash eft credit].freeze       # "credit" = an internal credit application
  KINDS   = %w[payment deposit credit_applied refund reversal].freeze

  belongs_to :billing_account, optional: true
  belongs_to :invoice, optional: true
  belongs_to :patient, optional: true   # a payment may be tied directly to a patient, not just an account

  validates :method, inclusion: { in: METHODS }
  validates :kind,   inclusion: { in: KINDS }
  # Cap well under the 4-byte integer max (2_147_483_647) so a fat-fingered huge amount is a
  # friendly validation error, never an ActiveModel::RangeError / 500. R20m >> any real payment.
  MAX_CENTS = 2_000_000_000
  validates :amount_cents, numericality: { greater_than: 0, less_than_or_equal_to: MAX_CENTS }
  validate  :must_have_an_owner
  before_validation { self.received_at ||= Time.current }

  after_create :apply_inbound_effect

  scope :active, -> { where(reversed_at: nil) }
  scope :inward, -> { where(kind: %w[payment deposit], reversed_at: nil) } # real money received

  def amount = amount_cents.to_i / 100.0
  def reversed? = reversed_at.present?

  # Undo a recorded payment/deposit: put the invoice balance or account credit back the way
  # it was. The row stays (marked reversed) for the audit trail and drops out of `active`.
  def reverse!(reason: nil)
    return false if reversed?
    return false unless %w[payment deposit].include?(kind)

    transaction do
      update!(reversed_at: Time.current, reason: reason)
      if kind == "payment" then invoice&.reduce_paid!(amount_cents)
      elsif kind == "deposit" then billing_account&.deduct_credit!(amount_cents)
      end
    end
    true
  end

  private

  # Compliance/audit: money can never be recorded detached from everything. Every payment
  # must identify whose money it is — at least an invoice, account, or patient.
  def must_have_an_owner
    return if invoice_id.present? || billing_account_id.present? || patient_id.present?

    errors.add(:base, "A payment must be linked to an invoice, account, or patient")
  end

  # Only genuine inward money auto-applies. credit_applied / refund / reversal rows are
  # created by explicit account flows that already moved the money — no auto effect here,
  # or they would double-count.
  def apply_inbound_effect
    case kind
    when "payment" then invoice&.register_payment!(amount_cents)
    when "deposit" then billing_account&.add_credit!(amount_cents)
    end
  end
end
