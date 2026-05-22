# A price for one procedure code within a fee schedule.
class FeeScheduleItem < ApplicationRecord
  belongs_to :fee_schedule
  belongs_to :procedure_code

  validates :procedure_code_id, uniqueness: { scope: :fee_schedule_id }
  validates :practice_fee_cents, numericality: { greater_than_or_equal_to: 0 }

  def practice_fee
    practice_fee_cents.to_i / 100.0
  end
end
