# Estimate macros for FILLINGS — the gap (RCT anterior/posterior, crown, implant macros
# already exist). The support bundle is derived from Dr Chalita's OWN Elixir co-occurrence
# over 24 months: every filling visit bills 8109 (infection control, x2) + 8110 (sterilised
# instrumentation); ~80-90% include 8145 (local anaesthetic); ~60-67% include 8304 (rubber dam).
# Searchable by access_code (e.g. "FILL POST 2"). Idempotent. Run:
#   bin/rails runner script/seed_filling_macros.rb
SUPPORT = [ [ "8109", 2 ], [ "8110", 1 ], [ "8145", 1 ], [ "8304", 1 ] ]
DEFS = [
  [ "FILL ANT 1",  "ANTERIOR FILLING - 1 SURFACE",    "8351" ],
  [ "FILL ANT 2",  "ANTERIOR FILLING - 2 SURFACES",   "8352" ],
  [ "FILL ANT 3",  "ANTERIOR FILLING - 3 SURFACES",   "8353" ],
  [ "FILL ANT 4",  "ANTERIOR FILLING - 4+ SURFACES",  "8354" ],
  [ "FILL POST 1", "POSTERIOR FILLING - 1 SURFACE",   "8367" ],
  [ "FILL POST 2", "POSTERIOR FILLING - 2 SURFACES",  "8368" ],
  [ "FILL POST 3", "POSTERIOR FILLING - 3 SURFACES",  "8369" ],
  [ "FILL POST 4", "POSTERIOR FILLING - 4+ SURFACES", "8370" ]
]

DEFS.each do |access, name, resin|
  m = TreatmentMacro.find_or_initialize_by(access_code: access)
  m.name = name
  m.active = true
  m.laboratory = false
  m.save!
  m.treatment_macro_items.destroy_all
  ([ [ resin, 1 ] ] + SUPPORT).each_with_index do |(code, qty), i|
    pc = ProcedureCode.find_by(code: code)
    unless pc
      puts "  WARN [#{access}] code #{code} not found — skipped"
      next
    end
    m.treatment_macro_items.create!(procedure_code: pc, tariff_code: pc.code, quantity: qty, position: i)
  end
  total = m.treatment_macro_items.includes(:procedure_code).sum { |it| (it.procedure_code&.default_fee_cents.to_i) * it.quantity } / 100.0
  puts "  [#{access}] #{name} -> #{m.treatment_macro_items.count} codes, est. total R#{total.round(2)}"
end
puts "Filling macros now: #{TreatmentMacro.where('access_code LIKE ?', 'FILL %').count}"
