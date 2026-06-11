# Finds the next open appointment slots for a provider — the booking-speed lever
# (reception no longer scans the diary grid by eye). The booking #create still
# validates overlaps, so this is a convenience finder, not the source of truth.
#
# Working hours come from DoctorSchedule (per weekday: active flag, start/end time,
# optional break) — configurable in Settings. Provider-specific schedules are
# preferred; otherwise any active practice schedule for that weekday is used.
class NextAvailableSlotFinder
  ZONE    = "Africa/Johannesburg".freeze
  STEP    = 15 # minutes
  HORIZON = 30 # days to look ahead

  def self.call(provider:, duration_min: 30, from: nil, limit: 3)
    return [] if provider.nil?

    Time.use_zone(ZONE) { new(provider, duration_min, from, limit).run }
  end

  def initialize(provider, duration_min, from, limit)
    @provider = provider
    @duration = duration_min.to_i.clamp(15, 240)
    @from     = from || Time.current
    @limit    = limit
  end

  def run
    @sched = load_schedules
    return [] if @sched.empty?

    window_end = @from + HORIZON.days
    busy = @provider.appointments
                    .where.not(status: %w[cancelled no_show])
                    .where(start_time: (@from - 1.day)..window_end)
                    .pluck(:start_time, :end_time)
                    .map { |s, e| [ s, e || s + 30.minutes ] }

    slots = []
    t = round_up(@from)
    guard = 0
    while slots.size < @limit && t < window_end && (guard += 1) < 8000
      day = @sched[t.wday]
      if day.nil? || @provider.on_leave_on?(t.to_date)
        t = next_open_day(t); next
      end
      tmin   = t.hour * 60 + t.min
      finish = t + @duration.minutes
      fmin   = tmin + @duration
      if tmin < day[:open_min]
        t = at_minute(t, day[:open_min]); next
      end
      if fmin > day[:close_min] || finish.to_date != t.to_date
        t = next_open_day(t); next
      end
      if day[:brk] && tmin < day[:brk][1] && fmin > day[:brk][0]
        t = at_minute(t, day[:brk][1]); next # slot overlaps the break → jump to break end
      end
      clash = busy.find { |bs, be| t < be && finish > bs }
      if clash
        t = round_up(clash[1]); next
      end
      slots << t
      t += @duration.minutes
    end
    slots.map(&:iso8601)
  end

  private

  # wday (0=Sun..6=Sat) => { open_min:, close_min:, brk: [start_min, end_min] | nil }.
  def load_schedules
    own      = DoctorSchedule.where(provider_id: @provider.id, active: true).index_by(&:day_of_week)
    fallback = DoctorSchedule.where(active: true).group_by(&:day_of_week)
    map = {}
    (0..6).each do |wd|
      s = own[wd] || fallback[wd]&.first
      next unless s&.start_time && s&.end_time

      bs = s.break_start ? mins(s.break_start) : nil
      be = s.break_end   ? mins(s.break_end)   : nil
      map[wd] = { open_min: mins(s.start_time), close_min: mins(s.end_time),
                  brk: (bs && be && be > bs ? [ bs, be ] : nil) }
    end
    map
  end

  def mins(t) = t.hour * 60 + t.min

  def round_up(time)
    step = STEP * 60
    Time.zone.at((time.to_i / step.to_f).ceil * step)
  end

  def at_minute(time, minute_of_day)
    time.change(hour: minute_of_day / 60, min: minute_of_day % 60)
  end

  def next_open_day(time)
    d = time.to_date + 1
    HORIZON.times do
      return at_minute(Time.zone.local(d.year, d.month, d.day, 0, 0, 0), @sched[d.wday][:open_min]) if @sched[d.wday]

      d += 1
    end
    time + HORIZON.days # nothing open in range → push past the window to end the scan
  end
end
