# Correct procedure-code fees to the most-common per-unit price (mode of amount/qty),
# fixing import outliers (e.g. crown 8409 was R27550 from a multi-tooth line). tmp/tariffs2.json
require "json"
data = JSON.parse(File.read("tmp/tariffs2.json"))
n = 0
data.each do |code, info|
  pc = ProcedureCode.find_by(code: code)
  next unless pc
  pc.update_columns(default_fee_cents: (info["fee"].to_f * 100).round)
  n += 1
end
puts "[tariff-fix] updated #{n} fees"
puts "[tariff-fix] 8409 crown R#{ProcedureCode.find_by(code: '8409')&.default_fee_cents.to_i / 100.0}, over-R10k codes: #{ProcedureCode.where('default_fee_cents > 1000000').count}"
