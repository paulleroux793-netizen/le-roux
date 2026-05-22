# The unit that owes money to the practice — a single patient or a family.
# The statement (which the patient submits to their own medical aid) is addressed here.
class BillingAccount < ApplicationRecord
  has_many :account_patients, dependent: :destroy
  has_many :patients, through: :account_patients
  belongs_to :head_patient, class_name: "Patient", optional: true

  validates :billing_name, presence: true
  validates :account_code, uniqueness: true, allow_nil: true

  # Generates the next sequential account code (e.g. "M0174") if not supplied.
  def self.next_account_code
    last = where("account_code ~ '^M[0-9]+$'").order(Arel.sql("LENGTH(account_code), account_code")).last
    n = last&.account_code.to_s.delete("M").to_i
    format("M%04d", n + 1)
  end
end
