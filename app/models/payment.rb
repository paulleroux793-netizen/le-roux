# A payment received at the practice (card / cash / EFT), optionally a deposit (e.g. whitening
# R2,000). If linked to an invoice, it updates that invoice's paid status.
class Payment < ApplicationRecord
  METHODS = %w[card cash eft].freeze

  belongs_to :billing_account, optional: true
  belongs_to :invoice, optional: true
  belongs_to :patient, optional: true   # a payment may be tied directly to a patient, not just an account

  validates :method, inclusion: { in: METHODS }
  validates :amount_cents, numericality: { greater_than: 0 }
  before_validation { self.received_at ||= Time.current }

  after_create :apply_to_invoice

  def amount = amount_cents.to_i / 100.0

  private

  def apply_to_invoice
    invoice&.register_payment!(amount_cents)
  end
end
