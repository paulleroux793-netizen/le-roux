# Imports the live Elixir diary as EDITABLE Ivory appointments, so the diary can
# be tested as if Ivory were live (drag, status, copy/paste) WITHOUT touching
# Elixir. Elixir stays the real system; this is Ivory's editable working copy.
#
# Idempotent: clears its own previously-imported rows (tagged [elixir-test]) and
# rebuilds. Patients matched to existing records by name; missing ones created.
# "Closed" rows become block-outs (CalendarNote). Per-dentist overlaps are skipped.
#
# Run on the rig:  bin/rails runner script/import_elixir_appointments.rb
require "json"

MARK = "[elixir-test]"
data = JSON.parse(File.read(ENV.fetch("LIVE_JSON", "tmp/diary_live.json")))

def norm(s) = s.to_s.downcase.gsub(/[^a-z ]/, " ").split.join(" ")

prov_by_norm = Provider.all.index_by { |p| norm(p.name) }

patients_by_name = {}
Patient.find_each do |p|
  patients_by_name[norm("#{p.first_name} #{p.last_name}")] ||= p
end

def resolve_patient(name, idx)
  n = norm(name)
  return idx[n] if idx[n]
  w = n.split
  return idx[w.first(2).join(" ")] if w.size >= 2 && idx[w.first(2).join(" ")]
  nil
end

stats = Hash.new(0)

# Clear any previous test import. FK-safe: drop dependents from EVERY table that
# references the appointment (notifications, scribe_sessions, confirmation_logs,
# summaries, …) before deleting the appointments themselves.
appt_ids = Appointment.where("notes LIKE ?", "%#{MARK}%").pluck(:id)
if appt_ids.any?
  conn = ActiveRecord::Base.connection
  ids = appt_ids.join(",")
  conn.tables.each do |t|
    next if t == "appointments"
    next unless conn.columns(t).map(&:name).include?("appointment_id")
    conn.execute("DELETE FROM #{conn.quote_table_name(t)} WHERE appointment_id IN (#{ids})") rescue nil
  end
  Appointment.where(id: appt_ids).delete_all
end
CalendarNote.where("note LIKE ?", "%#{MARK}%").destroy_all
# Remove orphaned [elixir-test] placeholder patients (no appointments left), but SKIP any
# that are referenced elsewhere (billing_accounts, form_submissions, …) — destroy per-record
# so an FK on one patient never aborts the whole import.
Patient.where("patients.notes LIKE ?", "%#{MARK}%").where.missing(:appointments).find_each do |orphan|
  orphan.destroy
rescue ActiveRecord::InvalidForeignKey
  next
end

data.each do |r|
  prov = prov_by_norm[norm(r["dentist"])]
  start_at = (Time.zone.parse(r["appointment_start_at"]) rescue nil)
  end_at   = (Time.zone.parse(r["appointment_end_at"]) rescue nil) || (start_at && start_at + 30.minutes)
  next unless start_at && end_at

  if r["patient_name"].to_s.strip.casecmp?("closed")
    CalendarNote.create!(provider_id: prov&.id, starts_at: start_at, ends_at: end_at, note: "Closed #{MARK}")
    stats[:blocks] += 1
    next
  end

  patient = resolve_patient(r["patient_name"], patients_by_name)
  unless patient
    parts = r["patient_name"].to_s.split
    fn = (parts.shift || "Unknown")
    ln = parts.join(" ").presence || "(Elixir)"
    stats[:patients_created] += 1
    # Patient requires a phone OR id_number; real demographics arrive in the
    # patient-import step, so use a clearly-marked synthetic id meanwhile.
    patient = Patient.create!(
      first_name: fn, last_name: ln,
      id_number: "ELX-IMPORT-#{stats[:patients_created]}",
      notes: "#{MARK} imported from Elixir diary"
    )
    patients_by_name[norm(r["patient_name"])] = patient
  end

  # allow_overlap: true — the diary is a faithful MIRROR of Elixir, which permits
  # same-dentist same-slot bookings. Skips the overlap guard (which still protects
  # native WhatsApp/web bookings, where allow_overlap stays false).
  Appointment.create!(
    patient:    patient,
    provider_id: prov&.id,
    start_time: start_at,
    end_time:   end_at,
    reason:     r["reason"],
    status:     :scheduled,
    allow_overlap: true,
    notes:      MARK
  )
  stats[:appointments] += 1
rescue ActiveRecord::RecordNotUnique, ActiveRecord::StatementInvalid
  stats[:skipped_overlap] += 1
rescue => e
  stats[:errors] += 1
  Rails.logger.warn("[elixir-test] skip row: #{e.class}: #{e.message}")
end

puts "[elixir-test] #{stats.inspect}"
puts "[elixir-test] Appointment total=#{Appointment.count}, future=#{Appointment.where('start_time >= ?', Time.current).count}"
