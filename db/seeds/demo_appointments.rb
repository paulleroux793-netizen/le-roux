# Demo appointment seed — populates the calendar with two weeks of
# varied appointments across the imported patient base so Paul can
# actually see what the system looks like with real activity.
#
# IDEMPOTENT: keyed off `reason: "[DEMO] ..."` so re-running this
# replaces just the demo set without touching real bookings.
#
# Run:  bundle exec rails runner db/seeds/demo_appointments.rb
#       (DESTROY existing demo set first; safe on every re-run)

DEMO_TAG = "[DEMO]".freeze

# Wipe prior demo set
removed = Appointment.where("reason LIKE ?", "#{DEMO_TAG}%").destroy_all
puts "demo_appointments: removed #{removed.size} prior demo rows"

# Pull a varied slice of patients — favour ones with phones so the
# calendar pop-over has real-looking data.
candidates = Patient.where.not(phone: nil).order("RANDOM()").limit(40).to_a
if candidates.size < 10
  puts "demo_appointments: not enough patients to seed"
  exit 0
end

# Reasons / durations that match the booking flow
SLOTS = [
  { reason: "Check-up + clean",      minutes: 45 },
  { reason: "Filling",               minutes: 30 },
  { reason: "Root canal — visit 1",  minutes: 60 },
  { reason: "Extraction",            minutes: 30 },
  { reason: "Crown prep",            minutes: 90 },
  { reason: "Whitening consultation", minutes: 30 },
  { reason: "Emergency — pain",      minutes: 30 },
  { reason: "Follow-up",             minutes: 30 },
]

# Build a 14-day calendar (today − 5 days to today + 8 days). Past
# entries get status = "completed", future = mix of scheduled / confirmed.
start_window = Date.current - 5
end_window   = Date.current + 8

created = 0
candidates.each_with_index do |patient, idx|
  day = (start_window + (idx % 14)).to_date
  next if [ 0 ].include?(day.wday) # skip Sundays — clinic closed

  slot = SLOTS[idx % SLOTS.size]
  hour = 8 + (idx % 8)               # 08h to 15h
  minute = [ 0, 15, 30, 45 ][idx % 4]
  start_at = day.in_time_zone("Africa/Johannesburg").change(hour: hour, min: minute)
  end_at   = start_at + slot[:minutes].minutes

  past = day < Date.current
  status = past ? "completed" : ([ "scheduled", "confirmed", "confirmed" ].sample)

  begin
    Appointment.create!(
      patient: patient,
      start_time: start_at,
      end_time: end_at,
      reason: "#{DEMO_TAG} #{slot[:reason]}",
      status: status
    )
    created += 1
  rescue ActiveRecord::RecordInvalid, ActiveRecord::StatementInvalid => e
    # Most likely collides with existing live appointment for the same
    # slot — skip and continue.
    next
  end
end

puts "demo_appointments: created #{created} demo rows across #{start_window} → #{end_window}"
puts "  past_completed=#{Appointment.where('reason LIKE ?', '%[DEMO]%').where('start_time < ?', Time.current).count}"
puts "  upcoming=#{Appointment.where('reason LIKE ?', '%[DEMO]%').where('start_time >= ?', Time.current).count}"
