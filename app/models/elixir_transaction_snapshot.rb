# Read-only snapshot of one billing line from an Elixir Transaction Analysis PDF.
class ElixirTransactionSnapshot < ApplicationRecord
  scope :for_date,        ->(d) { where(transaction_date: d) }
  scope :for_account,     ->(code) { where(account_code: code) }
  scope :for_dentist,     ->(name) { where(dentist: name) }
  scope :procedures_only, -> { where.not(procedure_code: %w[P-CARD P-CASH P-EFT]) }
  scope :payments_only,   -> { where(procedure_code: %w[P-CARD P-CASH P-EFT]) }

  # Aggregate the total billed across all procedure lines (excludes payments).
  def self.total_billed_for(date)
    for_date(date).procedures_only.sum(:debit)
  end

  # Aggregate payments received.
  def self.total_received_for(date)
    for_date(date).payments_only.sum(:credit)
  end
end
