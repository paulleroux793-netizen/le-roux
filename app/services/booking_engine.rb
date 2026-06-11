# Channel-agnostic appointment booking CORE — the SAME validate-and-create logic the WhatsApp
# bot uses (extracted from WhatsappService#attempt_booking), so the web chat widget books
# IDENTICALLY: no weekends, no after-hours, no double-booking. It SENDS NOTHING — each channel
# does its own post-booking (WhatsApp confirmation template, or the web widget's WhatsApp pack).
# Every guard rests on the SAME shared source of truth (PracticeConfig, DoctorSchedule,
# Appointment + the per-provider exclusion constraint), so web and WhatsApp cannot diverge.
class BookingEngine
  # status ∈ :booked :too_soon :public_holiday :outside_working_hours
  #          :after_hours_today :slot_taken :already_booked :invalid
  Result = Struct.new(:status, :appointment, :existing, keyword_init: true) do
    def booked? = status == :booked
    def recoverable? = %i[too_soon public_holiday outside_working_hours after_hours_today slot_taken].include?(status)
  end

  def self.call(**kwargs) = new.call(**kwargs)

  # message_after_hours: true when the inbound message arrived outside business hours
  # (mirrors WhatsApp's "message_arrived_after_hours" — holds future slots as pending,
  # rejects same-day). For the web widget pass currently_within_working_hours? -> negated.
  def call(patient:, date:, time:, treatment: nil, message_after_hours: false)
    start_time = Time.zone.parse("#{date} #{time}")
    return Result.new(status: :invalid) if start_time.nil?
    duration  = duration_for_treatment(treatment)
    end_time  = start_time + duration
    reason    = treatment.to_s.strip.empty? ? "Consultation" : treatment.capitalize

    earliest = Time.current + PracticeConfig.booking_buffer_minutes.minutes
    return Result.new(status: :too_soon) if start_time <= earliest
    return Result.new(status: :public_holiday) if public_holiday?(start_time.to_date)
    return Result.new(status: :outside_working_hours) unless slot_within_working_hours?(start_time, end_time)
    return Result.new(status: :after_hours_today) if message_after_hours && start_time.to_date == Date.current

    if slot_conflicts_locally?(start_time, end_time)
      own = own_overlapping(patient, start_time, end_time)
      return own ? Result.new(status: :already_booked, existing: own) : Result.new(status: :slot_taken)
    end

    is_whitening = treatment.to_s.downcase.match?(/whitening|biolase|bleiking|tandebleiking|bleach/)
    base_status  = (message_after_hours || is_whitening) ? :pending_confirmation : :scheduled
    notes        = is_whitening ? "awaiting R2,000 whitening deposit" : nil

    appt = patient.appointments.create!(
      start_time: start_time, end_time: end_time, reason: reason, status: base_status, notes: notes
    )
    Result.new(status: :booked, appointment: appt)
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::StatementInvalid => e
    # Concurrent/duplicate booking race — same resolution as WhatsApp: the per-provider
    # exclusion constraint rejected the insert because the slot was just taken.
    if e.message.include?("no_overlapping_appointments") ||
       (defined?(PG::ExclusionViolation) && e.cause.is_a?(PG::ExclusionViolation)) ||
       e.is_a?(ActiveRecord::RecordNotUnique)
      own = own_overlapping(patient, start_time, end_time)
      return own ? Result.new(status: :already_booked, existing: own) : Result.new(status: :slot_taken)
    end
    raise
  rescue ArgumentError, TypeError
    Result.new(status: :invalid)
  end

  # ---- guards: byte-for-byte the same checks WhatsappService uses, on the same sources ----
  def public_holiday?(date)
    return true if date.wday == 0 || date.wday == 6 # Sun/Sat = closed
    PracticeConfig.public_holiday_dates.include?(date)
  end

  def slot_within_working_hours?(start_time, end_time)
    schedule = DoctorSchedule.for_day(start_time.wday)
    return false unless schedule
    schedule.working?(start_time) && schedule.working?(end_time - 1.minute)
  end

  def slot_conflicts_locally?(start_time, end_time, exclude_appointment_id: nil)
    q = Appointment.where.not(status: :cancelled).where("start_time < ? AND end_time > ?", end_time, start_time)
    q = q.where.not(id: exclude_appointment_id) if exclude_appointment_id
    q.exists?
  end

  def duration_for_treatment(treatment)
    PracticeConfig.duration_for(treatment).minutes
  end

  private

  def own_overlapping(patient, start_time, end_time)
    patient.appointments.where.not(status: :cancelled)
           .where("start_time < ? AND end_time > ?", end_time, start_time)
           .order(:start_time).first
  end
end
