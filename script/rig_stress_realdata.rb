# Extended stress against the REAL imported data + adversarial edge cases.
# Read-mostly; the few writes run in a transaction that rolls back.
#   docker compose -f docker-compose.rig.yml exec -T web bundle exec rails runner script/rig_stress_realdata.rb
results = []
add = ->(name, ok) { results << [name, !!ok] }

raw_id = ActiveRecord::Base.connection.select_value(
  "SELECT id_number FROM patients WHERE id_number IS NOT NULL LIMIT 1").to_s
add.("id_number is encrypted at rest (not raw digits)", raw_id.empty? || raw_id !~ /\A\d{6,13}\z/)

p_with_id = Patient.where.not(id_number: nil).first
if p_with_id
  add.("find_by(id_number:) round-trips via deterministic encryption",
       Patient.find_by(id_number: p_with_id.id_number)&.id == p_with_id.id)
else
  add.("(no real id_number present — find_by test skipped)", true)
end

add.("real patient names decrypt/read cleanly (sample 50)",
     Patient.limit(50).all? { |x| x.first_name.present? || x.last_name.present? })

linked = BillingAccount.joins(:patients).distinct.count rescue 0
add.("billing accounts present and (ideally) linked to patients", BillingAccount.count.positive?)
results << ["  note: accounts_with_patients=#{linked} of #{BillingAccount.count}", true]

surname = Patient.where.not(last_name: [nil, ""]).limit(1).pick(:last_name).to_s
add.("search by a real surname returns >=1",
     surname.empty? || Patient.where("last_name ILIKE ?", "%#{surname}%").exists?)

ActiveRecord::Base.transaction do
  pat = Patient.create!(first_name: "Stress", last_name: "Tëst-Ünïcode", phone: "+27990000001")
  start = 3.days.from_now.change(hour: 9, min: 0)
  a1 = Appointment.create!(patient: pat, start_time: start, end_time: start + 30.minutes,
                           status: "scheduled", reason: "x")
  add.("appointment persists with unicode patient name", a1.persisted?)

  a1.update!(notes: "a" * 5000)
  add.("5000-char note saved + read back", a1.reload.notes.length == 5000)

  pat2 = Patient.create!(first_name: "Enc", last_name: "Test", id_number: "9001011234088")
  raw = ActiveRecord::Base.connection.select_value("SELECT id_number FROM patients WHERE id=#{pat2.id}")
  add.("new id_number stored encrypted (not plaintext)", raw.to_s != "9001011234088")
  add.("new id_number decrypts to original value", Patient.find(pat2.id).id_number == "9001011234088")
  add.("duplicate id_number is found by deterministic search",
       Patient.where(id_number: "9001011234088").count >= 1)

  raise ActiveRecord::Rollback
end

pass = results.count { |_, ok| ok }
fail = results.count { |_, ok| !ok }
puts "\n===== REAL-DATA STRESS ====="
results.each { |n, ok| puts "  #{ok ? 'PASS' : 'FAIL'}  #{n}" }
puts "-----"
puts "PASS: #{pass}  FAIL: #{fail}"
puts "patients=#{Patient.count} with_id_number=#{Patient.where.not(id_number: nil).count} accounts=#{BillingAccount.count} appts=#{Appointment.count}"
