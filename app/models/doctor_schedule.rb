class DoctorSchedule < ApplicationRecord
  DAY_NAMES = %w[sunday monday tuesday wednesday thursday friday saturday].freeze

  # optional during transition; each dentist has their own weekly schedule.
  belongs_to :provider, optional: true

  validates :day_of_week, presence: true,
            inclusion: { in: 0..6 },
            uniqueness: { scope: :provider_id }
  validates :start_time, presence: true, if: :active?
  validates :end_time, presence: true, if: :active?
  validate :end_time_after_start_time
  validate :break_within_working_hours

  scope :active, -> { where(active: true) }
  def self.for_day(day_number)
    find_by(day_of_week: day_number, active: true)
  end

  def day_name
    DAY_NAMES[day_of_week]
  end

  def working?(time)
    return false unless active?

    time_only = time.strftime("%H:%M:%S")
    within_hours = time_only >= start_time.strftime("%H:%M:%S") && time_only < end_time.strftime("%H:%M:%S")
    on_break = break_start.present? && break_end.present? &&
               time_only >= break_start.strftime("%H:%M:%S") && time_only < break_end.strftime("%H:%M:%S")

    within_hours && !on_break
  end

  private

  def end_time_after_start_time
    return if start_time.blank? || end_time.blank?

    if end_time <= start_time
      errors.add(:end_time, "must be after start time")
    end
  end

  def break_within_working_hours
    return if break_start.blank? || break_end.blank? || start_time.blank? || end_time.blank?

    if break_start < start_time || break_end > end_time
      errors.add(:base, "Break must be within working hours")
    end
  end
end
