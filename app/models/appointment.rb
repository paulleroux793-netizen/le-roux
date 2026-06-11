class Appointment < ApplicationRecord
  belongs_to :patient
  # optional during the transition; the diary always sets it. Backfilled to the
  # active provider for any pre-existing rows.
  belongs_to :provider, optional: true
  has_one :cancellation_reason, dependent: :destroy
  has_many :confirmation_logs, dependent: :destroy

  enum :status, {
    scheduled: 0,
    confirmed: 1,
    completed: 2,
    cancelled: 3,
    no_show: 4,
    rescheduled: 5,
    pending_confirmation: 6,
    arrived: 7,            # patient has checked in at reception
    in_consultation: 8     # patient is in the chair with the dentist
  }

  # Diary block colour follows the patient-journey STATUS (the practice's real
  # workflow): booked=white, confirmed=green, arrived=yellow, in the chair=blue,
  # completed=purple. (cancelled/no-show are muted; the diary hides cancelled.)
  STATUS_COLORS = {
    "scheduled"            => "#ffffff",
    "pending_confirmation" => "#ffffff",
    "rescheduled"          => "#ffffff",
    "confirmed"            => "#22c55e",
    "arrived"              => "#facc15",
    "in_consultation"      => "#3b82f6",
    "completed"            => "#8b5cf6",
    "no_show"              => "#9ca3af",
    "cancelled"            => "#e5e7eb"
  }.freeze

  def status_color
    STATUS_COLORS[status] || "#ffffff"
  end

  validates :start_time, presence: true
  validates :end_time, presence: true
  validates :google_event_id, uniqueness: true, allow_nil: true
  validate :end_time_after_start_time
  validate :no_overlapping_appointments, on: [ :create, :update ]
  before_validation :set_diary_defaults, on: :create

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

    # Scoped to the same provider: two dentists may hold the same clock time;
    # one dentist may not double-book. (Mirrors the per-provider DB exclusion.)
    conflict = Appointment
      .where.not(status: :cancelled)
      .where.not(id: id)
      .where(provider_id: provider_id)
      .where("start_time < ? AND end_time > ?", end_time, start_time)
      .exists?

    errors.add(:base, "This time slot conflicts with an existing appointment") if conflict
  end

  # On create: default to the first BOOKABLE dentist if reception didn't pick one.
  # This keeps new AI/default bookings off a dentist who's closed for bookings
  # (e.g. on maternity leave) and routes them to whoever is currently covering.
  def set_diary_defaults
    self.provider ||= Provider.default_booking_provider
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
