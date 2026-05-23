# N2 — AI-extracted appointment draft proposed from an inbound email.
# Always human-in-the-loop: the dentist or reception sees a "ready to
# confirm" card, never an auto-booked appointment.
class MailAppointmentDraft < ApplicationRecord
  STATUSES = %w[pending confirmed dismissed].freeze

  belongs_to :mail_message
  belongs_to :patient, optional: true
  belongs_to :confirmed_appointment, class_name: "Appointment", optional: true

  validates :status, inclusion: { in: STATUSES }
  scope :pending, -> { where(status: "pending") }
end
