# Dr Le Roux's working hours
# Monday-Friday: 08:00 - 17:00, lunch break 12:00 - 13:00
# Saturday & Sunday: closed

schedules = [
  { day_of_week: 0, active: false },                                                                    # Sunday
  { day_of_week: 1, start_time: "08:00", end_time: "17:00", break_start: "12:00", break_end: "13:00" }, # Monday
  { day_of_week: 2, start_time: "08:00", end_time: "17:00", break_start: "12:00", break_end: "13:00" }, # Tuesday
  { day_of_week: 3, start_time: "08:00", end_time: "17:00", break_start: "12:00", break_end: "13:00" }, # Wednesday
  { day_of_week: 4, start_time: "08:00", end_time: "17:00", break_start: "12:00", break_end: "13:00" }, # Thursday
  { day_of_week: 5, start_time: "08:00", end_time: "17:00", break_start: "12:00", break_end: "13:00" }, # Friday
  { day_of_week: 6, active: false }                                                                      # Saturday
]

schedules.each do |attrs|
  DoctorSchedule.find_or_create_by!(day_of_week: attrs[:day_of_week]) do |schedule|
    schedule.start_time = attrs[:start_time]
    schedule.end_time = attrs[:end_time]
    schedule.break_start = attrs[:break_start]
    schedule.break_end = attrs[:break_end]
    schedule.active = attrs.fetch(:active, true)
  end
end

puts "Seeded #{DoctorSchedule.count} doctor schedule entries"
