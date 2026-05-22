# A dated per-tooth observation/condition (the odontogram data). FDI tooth numbering.
class ToothChartEntry < ApplicationRecord
  CONDITIONS = %w[healthy caries filling crown bridge missing root_canal implant fracture extraction_planned].freeze

  belongs_to :patient
  belongs_to :course_of_treatment, optional: true
  belongs_to :treatment_item, optional: true

  validates :tooth_number, presence: true
  validates :condition, inclusion: { in: CONDITIONS }

  before_validation { self.noted_at ||= Time.current }

  # Latest condition per tooth for a patient (for rendering the current chart).
  scope :current_for, ->(patient) {
    where(patient: patient).order(noted_at: :desc)
  }
end
