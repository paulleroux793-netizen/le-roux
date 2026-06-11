# AI ESTIMATE COMPOSER — EVAL HARNESS (regression net). READ-ONLY, no DB mutation.
#
# A golden set of prompt -> must-include-codes assertions drawn from the practice's own
# Treatment Code Recipes (system/reference/estimate_assistant/treatment_code_recipes.md).
# Run AiService#compose_treatment_lines for each, assert the expected codes are present (and
# absent where they must not be), and report a pass/fail score.
#
# WHY: this is how we keep the composer best-in-market AND regression-proof — run it on EVERY
# prompt / grounding / model change; the score must not drop. Add every newly-found failure as
# a new case so it can never silently come back.
#
# Run on the rig:
#   docker compose -f docker-compose.rig.yml exec -T web bin/rails runner script/evals/composer_evals.rb

svc = AiService.new

# Each case: must (all present), must_any (>=1 present), must_not (none present),
# min_qty {code=>n} (summed qty>=n), per_tooth [teeth] (the `key` code appears once per tooth).
CASES = [
  { prompt: "root canal on tooth 26",          must: %w[8339 8340 8109 8110 8145 8304], min_qty: { "8340" => 2 } },
  { prompt: "crown on tooth 11",                must: %w[8409 8560 8570 8146] },
  { prompt: "simple extraction on tooth 46",    must: %w[8201], must_not: %w[8202] },
  { prompt: "teeth whitening",                  must: %w[8159 8308 8304], must_not: %w[8145], min_qty: { "8308" => 2 } },
  { prompt: "filling on tooth 36",              must_any: %w[8367 8368 8369 8370 8398] },
  { prompt: "check up and clean",               must: %w[8159], must_any: %w[8101 8104] },
  { prompt: "two crowns on tooth 21 and 11",    must: %w[8409], per_tooth: { key: "8409", teeth: %w[11 21] } },
  { prompt: "surgical removal of wisdom tooth 48", must: %w[8937 8220] },
  { prompt: "3-unit bridge on teeth 14, 15 and 16", must: %w[8443 8415 8447 8146 8560 8570], min_qty: { "8443" => 2, "8447" => 2, "8560" => 3, "8570" => 3 } },
  { prompt: "dental implant placement phase 1 on tooth 36", must: %w[9183 9187] },
  { prompt: "ceramic veneer on tooth 11",       must: %w[8552 8560 8570 8146] },
  { prompt: "upper partial denture cobalt chrome", must: %w[8255 8099], must_any: %w[8234 8235 8236 8237 8238 8241] },
  { prompt: "pulpotomy on baby tooth 54",       must: %w[8307] },
].freeze

passes = 0
details = []

CASES.each do |c|
  r = svc.compose_treatment_lines(c[:prompt])
  lines = Array(r["lines"])
  codes = lines.map { |l| l["code"].to_s }
  reasons = []

  Array(c[:must]).each { |m| reasons << "missing #{m}" unless codes.include?(m) }
  if c[:must_any] && (codes & c[:must_any]).empty?
    reasons << "none of #{c[:must_any].join('/')}"
  end
  Array(c[:must_not]).each { |m| reasons << "should NOT have #{m}" if codes.include?(m) }
  (c[:min_qty] || {}).each do |code, q|
    got = lines.select { |l| l["code"].to_s == code }.sum { |l| l["quantity"].to_i }
    reasons << "#{code} qty #{got}<#{q}" if got < q
  end
  if (pt = c[:per_tooth])
    teeth = lines.select { |l| l["code"].to_s == pt[:key] }.map { |l| l["tooth_number"].to_s }
    missing = pt[:teeth] - teeth
    reasons << "#{pt[:key]} missing on tooth #{missing.join(',')}" unless missing.empty?
  end

  ok = reasons.empty?
  passes += 1 if ok
  details << "#{ok ? '✅ PASS' : '❌ FAIL'}  #{c[:prompt]}  (#{codes.size} codes)#{ok ? '' : "  → #{reasons.join('; ')}"}"
end

puts details.join("\n")
pct = (100.0 * passes / CASES.size).round
puts "\nCOMPOSER EVAL SCORE: #{passes}/#{CASES.size} (#{pct}%)"
puts "STATUS: #{pct == 100 ? 'GREEN — no regressions' : "ATTENTION — #{CASES.size - passes} case(s) failing"}"
