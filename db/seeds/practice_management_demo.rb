# DEMO data for Ivory — a single clearly-fake patient with a course of treatment, so the
# clinical screens are reviewable before the real import runs. Idempotent. NOT real PII.
#   bundle exec rails runner db/seeds/practice_management_demo.rb
DEMO_PHONE = "+27000000999"

patient = Patient.find_or_create_by!(phone: DEMO_PHONE) do |p|
  p.first_name = "Demo"
  p.last_name  = "Patient (Ivory)"
end

account = BillingAccount.find_or_create_by!(account_code: "DEMO001") do |a|
  a.billing_name = "Demo Patient (Ivory)"
  a.phone = DEMO_PHONE
end
AccountPatient.find_or_create_by!(billing_account: account, patient: patient) { |ap| ap.relationship = "self" }

cot = CourseOfTreatment.find_or_create_by!(patient: patient, description: "Upper-left rehabilitation (demo)") do |c|
  c.setting = "in_chair"
  c.status = "active"
  c.billing_account = account
end

# Treatment items from real catalogue codes
{
  "8101" => { tooth: nil,  status: "completed" },   # oral exam
  "8341" => { tooth: "26", status: "completed" },   # restorative
  "8201" => { tooth: "28", status: "planned" },     # extraction
}.each do |code, opts|
  pc = ProcedureCode.find_by(code: code)
  next unless pc
  next if cot.treatment_items.exists?(procedure_code: pc, tooth_number: opts[:tooth])
  item = cot.treatment_items.create!(procedure_code: pc, tooth_number: opts[:tooth], status: "planned", provider_name: "Dr le Roux")
  item.complete! if opts[:status] == "completed"
end

# Tooth chart
[
  [ "26", "filling" ], [ "28", "extraction_planned" ], [ "16", "crown" ], [ "36", "root_canal" ], [ "47", "caries" ]
].each do |tooth, condition|
  next if ToothChartEntry.exists?(patient: patient, tooth_number: tooth, condition: condition)
  ToothChartEntry.create!(patient: patient, tooth_number: tooth, condition: condition, course_of_treatment: cot, noted_by: "Dr le Roux")
end

# A signed clinical note
unless cot.clinical_notes.exists?
  note = ClinicalNote.create!(patient: patient, course_of_treatment: cot,
    subjective: "Patient reports sensitivity upper-left.",
    objective: "Caries 26; 28 unrestorable.",
    assessment: "Caries 26; extraction indicated 28.",
    plan: "Restore 26; extract 28; review.")
  note.sign!(by: "Dr le Roux")
end

puts "Demo ready: patient=#{patient.id} cot=#{cot.id} items=#{cot.treatment_items.count} chart=#{ToothChartEntry.where(patient: patient).count} notes=#{cot.clinical_notes.count}"
