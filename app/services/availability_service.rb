class AvailabilityService
  SLOT_DURATION = 30.minutes
  LOOKAHEAD_DAYS = 14

  # Returns up to `limit` human-readable slot strings for display in the AI prompt,
  # starting from `from_date`. Slots respect DoctorSchedule working hours and break
  # times, exclude past times, and exclude slots conflicting with existing appointments.
  def next_available_slots(from_date: Date.current, limit: 5)
    slots = []
    date = from_date

    while slots.length < limit && date <= from_date + LOOKAHEAD_DAYS.days
      if date.wday.between?(1, 5) && !public_holiday?(date)
        slots.concat(available_slots_for_day(date, limit - slots.length))
      end
      date = date.next_day
    end

    slots
  end

  private

  # Never advertise a slot on a SA public holiday — same source BookingEngine rejects on, so the
  # slots we offer and what we can actually book never disagree.
  def public_holiday?(date)
    PracticeConfig.public_holiday_dates.include?(date)
  rescue StandardError
    false
  end

  def available_slots_for_day(date, limit)
    schedule = DoctorSchedule.for_day(date.wday)
    return [] unless schedule

    results = []
    current = Time.zone.parse("#{date} #{schedule.start_time.strftime('%H:%M')}")
    day_end = Time.zone.parse("#{date} #{schedule.end_time.strftime('%H:%M')}")

    while current < day_end && results.length < limit
      slot_end = current + SLOT_DURATION

      if slot_end <= day_end &&
         current > Time.current &&
         schedule.working?(current) &&
         !slot_taken?(current, slot_end)
        results << current.strftime("%A, %-d %B at %H:%M")
      end

      current += SLOT_DURATION
    end

    results
  end

  def slot_taken?(start_time, end_time)
    Appointment
      .where.not(status: :cancelled)
      .where("start_time < ? AND end_time > ?", end_time, start_time)
      .exists?
  end
end
