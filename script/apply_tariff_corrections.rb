# Applies corrected per-UNIT tariff fees (from tmp/fee_corrections.json) to
# ProcedureCode.default_fee_cents. The old import used the raw line AMOUNT and
# ignored QUANTITY, so codes billed in multiples held the multi-unit line total.
# Idempotent: only changes codes whose fee differs. Run on the rig:
#   docker compose ... exec -T web bin/rails runner script/apply_tariff_corrections.rb
require "json"

data = JSON.parse(File.read(ENV.fetch("CORRECTIONS", "/rails/tmp/fee_corrections.json")))
applied = 0
data.each do |c|
  pc = ProcedureCode.find_by(code: c["code"])
  next unless pc
  old = pc.default_fee_cents.to_i
  new_cents = c["new_cents"].to_i
  next if old == new_cents
  pc.update!(default_fee_cents: new_cents)
  applied += 1
  puts format("  %-6s R%-9.2f -> R%-9.2f  %s", c["code"], old / 100.0, new_cents / 100.0, pc.description.to_s[0, 32])
end
puts "Applied #{applied} of #{data.size} fee corrections. ProcedureCode total=#{ProcedureCode.count}"
