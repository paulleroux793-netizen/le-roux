# Mirrors the LIVE Elixir diary into Ivory's read-only ElixirDiarySnapshot table,
# so Ivory's diary shows the practice's current Elixir bookings (Elixir stays the
# source of truth; this is a read-only mirror). Source data is tmp/diary_live.json,
# extracted from a fresh copy of MDLDATA.FDB (EXPRESSAPPOINTMENTS + DIARYRESOURCE).
#
# Idempotent refresh: clears the snapshot range from the cutoff forward (removing
# any older PDF-imported rows for those dates) and reinserts the current set.
#
# Run on the rig:  bin/rails runner script/import_elixir_live.rb
require "json"

path   = ENV.fetch("LIVE_JSON", "tmp/diary_live.json")
cutoff = Date.parse(ENV.fetch("LIVE_CUTOFF", "2026-06-01"))
data   = JSON.parse(File.read(path))

# Unique index is (source_file, appointment_start_at). The diary has concurrent
# appointments (both dentists at the same time), so source_file is PER DENTIST,
# and we dedupe within a dentist's identical start slot (rare data quirk).
def source_for(dentist)
  key = dentist.to_s.downcase.gsub(/[^a-z]/, "")
  "elixir_live_#{key.presence || 'unknown'}"
end

ElixirDiarySnapshot.transaction do
  deleted = ElixirDiarySnapshot.where("diary_date >= ?", cutoff).delete_all
  seen = Hash.new(0)
  inserted = 0
  data.each do |r|
    base = source_for(r["dentist"])
    slot = [base, r["appointment_start_at"]]
    n = seen[slot]
    seen[slot] += 1
    # First booking in a slot uses the base key; genuine concurrent rows get a
    # suffix so the unique (source_file, start_at) index lets them all through.
    sf = n.zero? ? base : "#{base}_#{n}"
    ElixirDiarySnapshot.create!(
      diary_date:           r["diary_date"],
      appointment_start_at: r["appointment_start_at"],
      appointment_end_at:   r["appointment_end_at"],
      dentist:              r["dentist"],
      patient_name:         r["patient_name"],
      account_code:         r["account_code"],
      is_new_patient:       r["is_new_patient"],
      reason:               r["reason"],
      source_file:          sf,
      imported_at:          Time.current
    )
    inserted += 1
  end
  puts "[elixir_live] deleted #{deleted} pre-existing (>= #{cutoff}), inserted #{inserted}"
end

today = Date.current
puts "[elixir_live] snapshots from today forward: #{ElixirDiarySnapshot.where('diary_date >= ?', today).count}"
puts "[elixir_live] by dentist: #{ElixirDiarySnapshot.where("source_file LIKE 'elixir_live%'").group(:dentist).count.inspect}"
