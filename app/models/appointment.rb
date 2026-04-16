class Appointment < ApplicationRecord
  belongs_to :patient
  has_one :cancellation_reason, dependent: :destroy
  has_many :confirmation_logs, dependent: :destroy

  enum :status, {
    scheduled: 0,
    confirmed: 1,
    completed: 2,
    cancelled: 3,
    no_show: 4,
    rescheduled: 5
  }

  validates :start_time, presence: true
  validates :end_time, presence: true
  validates :google_event_id, uniqueness: true, allow_nil: true
  validate :end_time_after_start_time
  validate :no_overlapping_appointments, on: :create

  scope :upcoming, -> { where("start_time > ?", Time.current).where.not(status: :cancelled).order(:start_time) }
  scope :for_date, ->(date) { where(start_time: date.all_day) }

  # Phase 9.14 — single source of truth for dashboard cache invalidation.
  #
  # AppointmentsController#create / #update / #cancel / #confirm used to
  # call `expire_appointment_caches!` by hand, but the WhatsApp booking
  # path (WhatsappService#attempt_booking → GoogleCalendarService#book_appointment)
  # writes an Appointment row **without** going through the controller,
  # so the dev_page_cache for /appointments, /dashboard, and /reminders
  # stayed stale for up to 10 seconds after a WhatsApp booking. The
  # symptom was "I booked via WhatsApp and the calendar doesn't show it."
  #
  # Moving invalidation to an after_commit callback makes every write
  # path — controllers, WhatsApp, future jobs — automatically cache-
  # coherent. In test the cache store is :null_store so delete_matched
  # is a no-op; in prod dev_page_cache bypasses entirely (Solid Cache
  # still responds to delete_matched cleanly as a belt-and-braces).
  after_commit :expire_dashboard_page_caches

  private

  def expire_dashboard_page_caches
    return unless Rails.cache.respond_to?(:delete_matched)

    %w[appointments dashboard reminders].each do |prefix|
      Rails.cache.delete_matched(/\Adev-page-cache\/#{prefix}\//)
    end
    Rails.cache.delete("patients/index/stats")
  rescue NotImplementedError
    # Null store in test raises on delete_matched in some Rails versions
    # — swallow it so the callback never blocks a write.
    nil
  end


  def end_time_after_start_time
    return if start_time.blank? || end_time.blank?

    if end_time <= start_time
      errors.add(:end_time, "must be after start time")
    end
  end

  def no_overlapping_appointments
    return if start_time.blank? || end_time.blank?

    conflict = Appointment
      .where.not(status: :cancelled)
      .where.not(id: id)
      .where("start_time < ? AND end_time > ?", end_time, start_time)
      .exists?

    errors.add(:base, "This time slot conflicts with an existing appointment") if conflict
  end

  # After-hours bookings are allowed per practice policy. The WhatsApp
  # service informs the patient when a booking falls outside regular
  # hours, but no longer blocks creation.
  def after_hours?
    return false if start_time.blank? || end_time.blank?

    schedule = DoctorSchedule.for_day(start_time.wday)
    return false if schedule.nil?

    !(schedule.working?(start_time) && schedule.working?(end_time - 1.minute))
  end
end
