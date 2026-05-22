# Practice-management seed (Phase 1, P1.4). Idempotent — safe to re-run.
# Run with:  bundle exec rails runner db/seeds/practice_management.rb
#
# Loads, from repo CSVs extracted from the practice's real GoodX data:
#   - db/seed_data/procedure_codes.csv  (tariff codes + real median fees from a year of transactions)
#   - db/seed_data/dental_macros.csv    (the practice's "Dental Macro's.xlsx" bundles)
# Then builds a default "PRIVATE <year>" fee schedule from those fees.
#
# Does NOT touch any live table. Pure additive reference data.
require "csv"

SEED_DIR = Rails.root.join("db", "seed_data")

puts "== Seeding procedure codes =="
pc_count = 0
CSV.foreach(SEED_DIR.join("procedure_codes.csv"), headers: true) do |row|
  code = row["code"].to_s.strip
  next if code.empty?
  pc = ProcedureCode.find_or_initialize_by(code: code)
  pc.description           = row["description"].presence || "Tariff #{code}"
  pc.category             = row["category"].presence || "other"
  pc.vat_treatment        = %w[zero_rated standard].include?(row["vat_treatment"]) ? row["vat_treatment"] : "zero_rated"
  pc.tooth_specific       = row["tooth_specific"].to_s.upcase == "Y"
  pc.default_fee_cents    = row["default_fee_cents"].presence&.to_i
  pc.save!
  pc_count += 1
end
puts "  #{ProcedureCode.count} procedure codes (#{pc_count} processed)"

puts "== Seeding treatment macros =="
macro_rows = CSV.read(SEED_DIR.join("dental_macros.csv"), headers: true)
macro_rows.group_by { |r| r["access_code"] }.each do |access_code, lines|
  next if access_code.to_s.strip.empty?
  first = lines.first
  macro = TreatmentMacro.find_or_initialize_by(access_code: access_code.strip)
  macro.name       = first["name"].presence || access_code
  macro.laboratory = lines.any? { |l| l["laboratory"].to_s.upcase == "Y" }
  macro.save!
  macro.treatment_macro_items.delete_all # rebuild lines idempotently
  lines.each do |l|
    tc = l["tariff_code"].to_s.strip
    next if tc.empty?
    item = macro.treatment_macro_items.create!(
      tariff_code: tc,
      quantity: (l["quantity"].presence || 1).to_i,
      position: (l["position"].presence || 0).to_i,
      more_info: l["more_info"].presence
    )
    item.resolve_procedure_code!
  end
end
linked = TreatmentMacroItem.where.not(procedure_code_id: nil).count
puts "  #{TreatmentMacro.count} macros, #{TreatmentMacroItem.count} lines (#{linked} linked to a catalogue code)"

puts "== Building PRIVATE fee schedule =="
year = Date.current.year
schedule = FeeSchedule.find_or_create_by!(name: "PRIVATE #{year}", year: year, medical_scheme_id: nil)
fs_count = 0
ProcedureCode.where.not(default_fee_cents: nil).find_each do |pc|
  item = FeeScheduleItem.find_or_initialize_by(fee_schedule: schedule, procedure_code: pc)
  item.practice_fee_cents = pc.default_fee_cents
  item.save!
  fs_count += 1
end
puts "  fee schedule '#{schedule.name}' with #{fs_count} priced items"

puts "== Done =="
