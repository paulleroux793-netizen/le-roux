# Dump ProcedureCodes + TreatmentMacros (+items) from LIVE to JSON so staging can mirror
# them for review. Run on live:  bin/rails runner script/export_for_staging.rb
require "json"
data = {
  "procedure_codes" => ProcedureCode.all.map { |c| c.attributes.except("id", "created_at", "updated_at") },
  "macros" => TreatmentMacro.all.map { |m|
    {
      "macro" => m.attributes.except("id", "created_at", "updated_at"),
      "items" => m.treatment_macro_items.order(:position).map { |i|
        { "tariff_code" => (i.procedure_code&.code || i.tariff_code), "quantity" => i.quantity, "position" => i.position, "more_info" => i.more_info }
      }
    }
  }
}
File.write("/rails/tmp/staging_seed.json", JSON.generate(data))
puts "exported #{data['procedure_codes'].size} codes + #{data['macros'].size} macros -> /rails/tmp/staging_seed.json"
