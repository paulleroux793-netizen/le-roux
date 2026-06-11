# script/data-cleanup/ambiguous_phones.rb  (DATA ITEM #3 — for Paul)
#
# WHAT: Lists patient phone numbers that don't normalise to a clean SA +27XXXXXXXXX
#       (27 + exactly 9 digits). WHY: a handful were entered with an extra/odd digit.
# RISK: LOW to run (this script is REPORT-ONLY — it makes NO writes at all).
#
# IMPORTANT FINDING (2026-06-06 read-only inspection, 1868 patients with a phone):
#   10 numbers don't match. They split into two groups:
#     • LEGIT FOREIGN (leave alone): +64 (NZ), +31 (NL) — real overseas patients.
#     • SA WITH AN EXTRA DIGIT (+27 + 10 digits = 12 total, should be 11): these are
#       AMBIGUOUS — we cannot know which digit is wrong, so there is NO safe
#       automatic fix. Each must be MANUALLY verified by reception against the
#       patient's real number, then corrected one at a time.
#
# So this item has NO APPLY mode — auto-"fixing" an ambiguous number could write a
# WRONG number onto a patient. The deliverable is this report; Paul/reception fixes
# each SA one manually via the patient edit screen after confirming the real number.
#
# USAGE (read-only):  bin/rails runner script/data-cleanup/ambiguous_phones.rb

ZA = /\A27\d{9}\z/ # canonical: 27 + 9 digits

foreign = []
sa_extra = []
other = []

Patient.where.not(phone: [ nil, "" ]).find_each do |p|
  digits = p.phone.to_s.gsub(/\D/, "")
  norm   = digits.sub(/\A0/, "27") # local 0XXXXXXXXX -> 27XXXXXXXXX
  next if norm =~ ZA               # already clean (or cleanly normalisable)

  row = { id: p.id, name: [ p.first_name, p.last_name ].compact.join(" "), phone: p.phone, digits: digits }
  if digits =~ /\A(?!27)\d{8,}\z/ && digits !~ /\A0/
    foreign << row                 # starts with a non-27 country code
  elsif digits =~ /\A27\d{10}\z/
    sa_extra << row                # 27 + 10 digits (one too many)
  else
    other << row
  end
end

puts "=== Ambiguous phone numbers report (READ-ONLY, no changes made) ==="
puts "Patients with a phone: #{Patient.where.not(phone: [ nil, '' ]).count}"
puts

puts "LEGIT FOREIGN (#{foreign.size}) — LEAVE ALONE (real overseas numbers):"
foreign.each { |r| puts "  ##{r[:id]} #{r[:name]} — #{r[:phone]}" }
puts

puts "SA WITH EXTRA DIGIT (#{sa_extra.size}) — MANUAL REVIEW (12 digits, should be 11; which digit is wrong is unknowable — confirm the real number with the patient, then edit):"
sa_extra.each { |r| puts "  ##{r[:id]} #{r[:name]} — #{r[:phone]}  (#{r[:digits].length} digits)" }
puts

unless other.empty?
  puts "OTHER / UNCLEAR (#{other.size}) — MANUAL REVIEW:"
  other.each { |r| puts "  ##{r[:id]} #{r[:name]} — #{r[:phone]}" }
  puts
end

puts "=== No automatic correction is applied or safe. Reception must fix each SA/other case by hand. ==="
