# Load ProcedureCodes + TreatmentMacros (+items) into STAGING from the live export, so the
# filling macros can be reviewed against real codes/fees. Idempotent. Run on staging:
#   bin/rails runner script/import_for_staging.rb
require "json"
d = JSON.parse(File.read("/rails/tmp/staging_seed.json"))

d["procedure_codes"].each do |attrs|
  pc = ProcedureCode.find_or_initialize_by(code: attrs["code"])
  pc.assign_attributes(attrs)
  pc.save!
end

d["macros"].each do |entry|
  m = TreatmentMacro.find_or_initialize_by(access_code: entry["macro"]["access_code"])
  m.assign_attributes(entry["macro"])
  m.save!
  m.treatment_macro_items.destroy_all
  entry["items"].each do |it|
    pc = ProcedureCode.find_by(code: it["tariff_code"])
    m.treatment_macro_items.create!(procedure_code: pc, tariff_code: it["tariff_code"], quantity: it["quantity"], position: it["position"], more_info: it["more_info"])
  end
end
puts "staging now: ProcedureCode=#{ProcedureCode.count} TreatmentMacro=#{TreatmentMacro.count}"
