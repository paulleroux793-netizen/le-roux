# Join: links a Patient to the BillingAccount that pays for them.
# Keeps the live `patients` table untouched (no FK column added there).
class AccountPatient < ApplicationRecord
  RELATIONSHIPS = %w[self head dependant guardian].freeze

  belongs_to :billing_account
  belongs_to :patient

  validates :relationship, inclusion: { in: RELATIONSHIPS }
  validates :patient_id, uniqueness: { scope: :billing_account_id }
end
