# Backfill billing accounts for patients created via the online intake / WhatsApp that never got
# an account number, using the practice's surname-initial scheme. SKIPS placeholders/test rows and
# likely duplicates (same name / ID / phone as another record). Honours the intake form's
# "responsible person": when the payer differs (rp_same_as_patient = false) the account groups
# under the PAYER (family shares one account). Signed-intake patients are marked POPIA-consented.
#
#   (default)  -> DRY-RUN: print the plan + the skipped list, write nothing.
#   APPLY=1    -> create the accounts for the clean list.
dry = ENV["APPLY"] != "1"

JUNK = /\bwhatsapp patient\b|\bnophone\b|\btest\b|aesthetics| - /i

def patient_details(patient)
  sub = patient.form_submissions.joins(:form_template)
               .where(form_templates: { key: "patient_details" }).order(:created_at).last
  return nil unless sub
  raw = sub.data
  d = raw.is_a?(Hash) ? raw : (JSON.parse(raw) rescue nil)
  d && (d["patient_details"].is_a?(Hash) ? d["patient_details"] : d)
end

norm = ->(p) { p.full_name.to_s.downcase.gsub(/[^a-z ]/, " ").squeeze(" ").strip }

# Duplicate indices across the WHOLE patient table -------------------------------
name_count  = Hash.new(0)
id_count    = Hash.new(0)
phone_count = Hash.new(0)
Patient.find_each do |p|
  name_count[norm.call(p)] += 1
  id_count[p.id_number.to_s.strip]   += 1 if p.id_number.present?
  phone_count[p.phone.to_s.strip]    += 1 if p.phone.present?
end

account_less = Patient.left_joins(:account_patients).where(account_patients: { id: nil })
                      .order(:last_name, :first_name).to_a

skipped = []
clean   = []
account_less.each do |p|
  if p.full_name =~ JUNK
    skipped << [ p, "placeholder/note" ]
  elsif name_count[norm.call(p)] > 1
    skipped << [ p, "duplicate name" ]
  elsif p.id_number.present? && id_count[p.id_number.to_s.strip] > 1
    skipped << [ p, "duplicate ID number" ]
  elsif p.phone.present? && phone_count[p.phone.to_s.strip] > 1
    skipped << [ p, "duplicate phone" ]
  else
    clean << p
  end
end

# Build the plan for the clean list ---------------------------------------------
plan = clean.map do |p|
  pd   = patient_details(p)
  same = pd.nil? || pd["rp_same_as_patient"].to_s != "false"
  if same
    surname = p.last_name.to_s; billing = p.full_name; payer_key = "self:#{p.id}"
  else
    rp_first = pd["rp_first_name"].to_s.strip; rp_last = pd["rp_last_name"].to_s.strip
    surname  = rp_last.presence || p.last_name.to_s
    billing  = [ rp_first, rp_last ].reject(&:blank?).join(" ").presence || p.full_name
    payer_key = "payer:#{surname.downcase}:#{rp_first.downcase}:#{pd['rp_id_number']}"
  end
  { patient: p, surname: surname, billing: billing, payer_key: payer_key, consent: !pd.nil?, same: same }
end

# Assign codes (a payer/family shares one), simulating the running sequence ------
payer_code = {}
seq = Hash.new { |h, k| h[k] = BillingAccount.next_account_code(k)[1..].to_i - 1 }
rows = plan.map do |r|
  if payer_code[r[:payer_key]]
    code = payer_code[r[:payer_key]]
  else
    initial = (r[:surname].gsub(/[^A-Za-z]/, "")[0] || "Z").upcase
    initial = "Z" unless initial.match?(/[A-Z]/)
    seq[initial] += 1
    code = format("%s%04d", initial, seq[initial])
    payer_code[r[:payer_key]] = code
  end
  r.merge(code: code)
end

puts "===== WILL CREATE (#{rows.size} patients -> #{payer_code.size} accounts) ====="
rows.each { |r| puts format("  %-28s %-8s %s%s", r[:patient].full_name, r[:code], (r[:same] ? "" : "[family] "), (r[:consent] ? "+consent" : "")) }
puts "===== SKIPPED for your review (#{skipped.size}) ====="
skipped.each { |p, why| puts format("  %-40s %s", p.full_name, why) }
puts "mode=#{dry ? 'DRY-RUN (no writes)' : 'APPLY'}"

unless dry
  created = 0
  rows.group_by { |r| r[:code] }.each do |code, members|
    ba = BillingAccount.find_or_create_by!(account_code: code) { |a| a.billing_name = members.first[:billing] }
    members.each do |m|
      ba.update!(head_patient_id: m[:patient].id) if m[:same] && ba.head_patient_id.blank?
      AccountPatient.find_or_create_by!(billing_account: ba, patient: m[:patient]) { |ap| ap.relationship = m[:same] ? "self" : "dependant" }
      if m[:consent] && m[:patient].consent_to_ai_processing_at.blank?
        m[:patient].update!(consent_to_ai_processing_at: Time.current, consent_to_ai_processing_by: "Online intake form (signed)")
      end
    end
    created += 1
  end
  puts "APPLIED: #{created} accounts created/linked."
end
