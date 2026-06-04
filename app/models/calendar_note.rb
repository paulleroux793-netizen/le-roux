class CalendarNote < ApplicationRecord
  # optional: a nil provider = the block applies to the whole practice (all
  # columns); a set provider = a "Closed"/blocked period in that dentist's column.
  belongs_to :provider, optional: true

  validates :starts_at, :ends_at, :note, presence: true
  validate :ends_after_starts

  scope :between, ->(range_start, range_end) { where(starts_at: range_start..range_end) }

  private

  def ends_after_starts
    return if starts_at.blank? || ends_at.blank?
    errors.add(:ends_at, "must be after the start time") if ends_at <= starts_at
  end
end
