# A preventive recall (6-month check-up / hygiene / follow-up). Outbound/additive — contacting the
# patient goes over WhatsApp via an additive job; never touches the live incoming flow.
class Recall < ApplicationRecord
  TYPES = %w[checkup hygiene followup].freeze
  STATUSES = %w[due contacted booked done cancelled].freeze

  belongs_to :patient

  validates :recall_type, inclusion: { in: TYPES }
  validates :status, inclusion: { in: STATUSES }
  validates :due_on, presence: true

  scope :due, -> { where(status: "due") }
  scope :overdue, -> { where(status: "due").where("due_on < ?", Date.current) }
end
