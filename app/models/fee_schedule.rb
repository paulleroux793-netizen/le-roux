# A price list (e.g. "PRIVATE 2026"). For this non-claiming practice the private list
# is the live one; scheme lists are reference-only for the self-claim statement.
class FeeSchedule < ApplicationRecord
  belongs_to :medical_scheme, optional: true
  has_many :fee_schedule_items, dependent: :destroy
  has_many :procedure_codes, through: :fee_schedule_items

  validates :name, presence: true

  scope :active, -> { where(active: true) }
  scope :private_lists, -> { where(medical_scheme_id: nil) }
end
