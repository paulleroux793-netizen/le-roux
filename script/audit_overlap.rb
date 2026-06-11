prov = Provider.active.first
prov2 = Provider.active.where.not(id: prov.id).first
p = Patient.first
base = (Date.current + 60).to_time.change(hour: 9)
cleanup = []
a1 = Appointment.create!(patient: p, provider: prov, start_time: base, end_time: base + 30*60, status: "scheduled", reason: "[audit] base")
cleanup << a1
# 1) same-provider overlap → should be INVALID
a2 = Appointment.new(patient: p, provider: prov, start_time: base + 10*60, end_time: base + 40*60, status: "scheduled", reason: "[audit] overlap")
puts "1 same-provider overlap blocked: #{!a2.valid?}  (#{a2.errors[:base].first})"
# 2) different provider same time → should be VALID
if prov2
  a3 = Appointment.new(patient: p, provider: prov2, start_time: base + 10*60, end_time: base + 40*60, status: "scheduled", reason: "[audit] other prov")
  puts "2 different-provider allowed: #{a3.valid?}"
else
  puts "2 (only one provider — skipped)"
end
# 3) adjacent (back-to-back, no overlap) → should be VALID
a4 = Appointment.new(patient: p, provider: prov, start_time: base + 30*60, end_time: base + 60*60, status: "scheduled", reason: "[audit] adjacent")
puts "3 back-to-back (no overlap) allowed: #{a4.valid?}"
# 4) cancel base → slot should free up
a1.update_column(:status, "cancelled")
a5 = Appointment.new(patient: p, provider: prov, start_time: base + 10*60, end_time: base + 40*60, status: "scheduled", reason: "[audit] after cancel")
puts "4 after cancelling base, slot freed: #{a5.valid?}"
cleanup.each(&:destroy)
puts "[audit] done, cleaned up"
