# Refresh ProcedureCode fees to the latest real billed (VAT-inclusive) amounts
# from Elixir, and add any billed codes Ivory was missing. Idempotent upsert by code.
require "json"
data = JSON.parse(File.read(ENV.fetch("TARIFFS_JSON", "tmp/tariffs.json")))
s = Hash.new(0)
data.each do |r|
  code = r["code"].to_s.strip
  next if code.blank?
  pc = ProcedureCode.find_or_initialize_by(code: code)
  newrec = pc.new_record?
  pc.description       = r["description"] if pc.description.blank? && r["description"].present?
  pc.default_fee_cents = (r["fee"].to_f * 100).round
  pc.vat_treatment     = "standard" if r["vat"].to_s == "15"
  pc.vat_treatment   ||= "standard"
  pc.category        ||= "other"
  pc.active            = true if newrec
  pc.save!
  s[newrec ? :created : :updated] += 1
rescue => e
  s[:errors] += 1; Rails.logger.warn("[tariff] #{code}: #{e.message}")
end
puts "[tariff] #{s.inspect}; total ProcedureCode=#{ProcedureCode.count}, priced=#{ProcedureCode.where.not(default_fee_cents: nil).count}"
