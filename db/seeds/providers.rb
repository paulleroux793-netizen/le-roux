# Two-dentist diary: providers + per-provider weekly schedules + backfill.
# Idempotent. Run:  bundle exec rails runner db/seeds/providers.rb
chalita = Provider.find_or_create_by!(name: "Dr Chalita le Roux") do |p|
  p.short_name = "Dr Chalita"
  p.color = "#0ea5e9"
  p.position = 1
  p.active = true
end
eliska = Provider.find_or_create_by!(name: "Dr Eliska Robinson") do |p|
  p.short_name = "Dr Eliska"
  p.color = "#14b8a6"
  p.position = 2
  p.active = true
end

# Per-provider weekly schedule: Mon–Fri 08:00–17:00, closed weekends.
[ chalita, eliska ].each do |prov|
  (0..6).each do |dow|
    working = (1..5).cover?(dow)
    DoctorSchedule.find_or_create_by!(provider_id: prov.id, day_of_week: dow) do |s|
      s.active = working
      if working
        s.start_time = "08:00"
        s.end_time = "17:00"
      end
    end
  end
end

# Drop any legacy global (provider-less) schedules now that schedules are per-provider.
DoctorSchedule.where(provider_id: nil).delete_all

# Backfill existing appointments to the currently-working dentist (Eliska; Dr
# Chalita is on maternity leave until 3 Aug 2026). Reception can reassign in the diary.
Appointment.where(provider_id: nil).update_all(provider_id: eliska.id)

puts "providers=#{Provider.count} schedules=#{DoctorSchedule.count} " \
     "appts_with_provider=#{Appointment.where.not(provider_id: nil).count}/#{Appointment.count}"
