# A named bundle of procedure codes (imported from "Dental Macro's.xlsx").
# One macro (e.g. "BRIDGE 3") expands into many billable line items with quantities —
# the GoodX time-saver, seeded from the practice's own macro file.
class TreatmentMacro < ApplicationRecord
  has_many :treatment_macro_items, -> { order(:position) }, dependent: :destroy
  has_many :procedure_codes, through: :treatment_macro_items

  validates :access_code, presence: true, uniqueness: true
  validates :name, presence: true

  scope :active, -> { where(active: true) }
end
