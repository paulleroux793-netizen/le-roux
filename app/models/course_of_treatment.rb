# An episode of care — groups treatment items and carries payor/setting/auth context.
# The bridge between clinical charting and billing (Phase 3 turns completed items into invoice lines).
class CourseOfTreatment < ApplicationRecord
  # Grammatically-correct plural; Rails would otherwise expect "course_of_treatments".
  self.table_name = "courses_of_treatment"

  SETTINGS = %w[in_chair hospital_chair hospital_theatre sedation].freeze
  STATUSES = %w[planned active completed closed].freeze

  belongs_to :patient
  belongs_to :billing_account, optional: true
  belongs_to :scheme_membership, optional: true
  has_many :treatment_items, dependent: :destroy
  has_many :clinical_notes, dependent: :nullify
  has_many :tooth_chart_entries, dependent: :nullify
  has_many :estimates, dependent: :nullify
  has_many :invoices, dependent: :nullify

  validates :setting, inclusion: { in: SETTINGS }
  validates :status, inclusion: { in: STATUSES }

  scope :open, -> { where(status: %w[planned active]) }

  # Total of items not voided, in Rand.
  def estimated_total
    treatment_items.where.not(status: "voided").sum(:fee_cents).to_i / 100.0
  end

  def completed_total
    treatment_items.where(status: "completed").sum(:fee_cents).to_i / 100.0
  end
end
