# A dentist who has their own diary column (Dr Chalita le Roux, Dr Eliska Robinson).
# Mirrors the Elixir "Provider" on each account + the per-dentist diary columns.
class Provider < ApplicationRecord
  has_many :appointments, dependent: :nullify
  has_many :doctor_schedules, dependent: :destroy
  has_many :calendar_notes, dependent: :nullify

  validates :name, presence: true, uniqueness: true

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:position, :name) }
  # Providers open for NEW bookings right now (excludes e.g. a dentist on
  # maternity leave). AI + default bookings route to the first of these.
  scope :bookable, -> { active.where(accepting_bookings: true) }

  # The provider new AI/default bookings should be assigned to.
  def self.default_booking_provider
    bookable.ordered.first || active.ordered.first
  end

  # True if this provider's diary is CLOSED on `date` (on leave up to and
  # including unavailable_until). Purely date-based so the column re-opens
  # automatically after the leave end date. The `accepting_bookings` flag is the
  # separate switch that routes new AI/default bookings away while on leave.
  def on_leave_on?(date)
    unavailable_until.present? && date.to_date <= unavailable_until
  end

  # Short label for the diary column header / account "Provider" field.
  def display_name
    short_name.presence || name
  end
end
