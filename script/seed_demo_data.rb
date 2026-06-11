# Demo data: families (main member + dependants) with varied invoices (amounts,
# providers, paid/unpaid) and different estimate types. Clearly tagged ([demo] notes
# + DEMO account codes) so it's identifiable and re-runnable.
require "json"
MARK = "[demo]"

# ── clear previous demo run (FK-safe: accounts + head_patient_id BEFORE patients) ──
oid = Patient.where("notes LIKE ?", "%#{MARK}%").pluck(:id)
BillingAccount.where("account_code LIKE 'DEMO%'").each do |a|
  a.invoices.each { |i| i.invoice_lines.delete_all; i.delete }
  Estimate.where(billing_account_id: a.id).each { |e| e.estimate_lines.delete_all; e.delete }
  a.payments.delete_all
  a.account_patients.delete_all
  a.update_columns(head_patient_id: nil)
  a.delete
end
if oid.any?
  Invoice.where(patient_id: oid).each { |i| i.invoice_lines.delete_all; i.delete }
  Estimate.where(patient_id: oid).each { |e| e.estimate_lines.delete_all; e.delete }
  Payment.where(patient_id: oid).delete_all
  Notification.where(patient_id: oid).delete_all rescue nil
  AccountPatient.where(patient_id: oid).delete_all
  BillingAccount.where(head_patient_id: oid).update_all(head_patient_id: nil)
  Patient.where(id: oid).delete_all
end

# ── real procedure codes for realistic amounts ──
def pc(code, fallback_cents) = ProcedureCode.find_by(code: code) || OpenStruct.new(code: code, description: code, default_fee_cents: fallback_cents, vat_treatment: "standard")
require "ostruct"
EXAM  = pc("8101", 69930);  CLEAN = pc("8155", 60000)
RESIN = pc("8351", 76807);  CROWN = pc("8409", 290900)
STERIL= pc("8110", 14973);  INFCTL= pc("8109", 13079)
EXTRACT = pc("8201", 95000)

CH = "DR CHALITA LE ROUX"; EL = "DR ELISKA ROBINSON"

def add_lines(doc, items)
  total = 0
  items.each do |c, tooth, qty|
    cents = c.default_fee_cents.to_i
    attrs = { code: c.code, description: c.description, quantity: (qty || 1),
              unit_fee_cents: cents, vat_treatment: (c.vat_treatment.presence || "standard") }
    attrs[:tooth_number] = tooth if tooth
    doc.is_a?(Invoice) ? doc.invoice_lines.create!(attrs) : doc.estimate_lines.create!(attrs)
    total += cents * (qty || 1)
  end
  total
end

def patient!(first, last, opts = {})
  Patient.create!({ first_name: first, last_name: last, notes: "[demo] demo patient" }.merge(opts))
end

stats = Hash.new(0)
phone_seq = 1

FAMILIES = [
  { code: "DEMO001", name: "John Demo-Smith", holder: ["John", "Demo-Smith", { date_of_birth: "1979-04-12" }],
    deps: [["Jane", "Demo-Smith", "spouse", { date_of_birth: "1981-08-03" }], ["Tommy", "Demo-Smith", "dependant", { date_of_birth: "2013-02-20" }]] },
  { code: "DEMO002", name: "Priya Demo-Naidoo", holder: ["Priya", "Demo-Naidoo", { date_of_birth: "1986-11-25" }],
    deps: [["Arun", "Demo-Naidoo", "dependant", { date_of_birth: "2016-06-09" }]] },
  { code: "DEMO003", name: "Pieter Demo-Botha", holder: ["Pieter", "Demo-Botha", { date_of_birth: "1964-01-30" }], deps: [] },
  { code: "DEMO004", name: "Aisha Demo-Khan", holder: ["Aisha", "Demo-Khan", { date_of_birth: "1992-09-14" }],
    deps: [["Zaid", "Demo-Khan", "dependant", { date_of_birth: "2019-03-01" }], ["Leila", "Demo-Khan", "dependant", { date_of_birth: "2021-07-22" }]] },
]

FAMILIES.each do |f|
  ba = BillingAccount.create!(account_code: f[:code], billing_name: f[:name], email: "#{f[:code].downcase}@demo.test")
  head = patient!(f[:holder][0], f[:holder][1], { phone: format("+2772000%04d", phone_seq) }.merge(f[:holder][2]))
  phone_seq += 1
  AccountPatient.create!(billing_account: ba, patient: head, relationship: "head")
  ba.update!(head_patient_id: head.id)
  members = [ head ]
  f[:deps].each do |fn, ln, rel, o|
    d = patient!(fn, ln, { id_number: "DEMO#{f[:code]}#{phone_seq}" }.merge(o)); phone_seq += 1
    AccountPatient.create!(billing_account: ba, patient: d, relationship: (rel == "spouse" ? "dependant" : "dependant"))
    members << d
  end
  stats[:patients] += members.size

  # Invoices — varied amounts/providers/dates/paid-state. Save FIRST, then add lines.
  inv1 = Invoice.create!(billing_account: ba, patient: head, invoice_date: Date.current - 40, provider_name: CH, status: "open", subtotal_cents: 0, vat_cents: 0, total_cents: 0, notes: MARK)
  t1 = add_lines(inv1, [[EXAM, nil, 1], [INFCTL, nil, 1], [STERIL, nil, 1]])
  inv1.update!(subtotal_cents: (t1/1.15).round, vat_cents: (t1 - t1/1.15).round, total_cents: t1, paid_cents: t1, status: "paid")
  Payment.create!(billing_account: ba, patient: head, amount_cents: t1, method: "card", received_at: (Date.current - 40).to_time, notes: MARK)

  inv2 = Invoice.create!(billing_account: ba, patient: members.last, invoice_date: Date.current - 12, provider_name: EL, status: "open", subtotal_cents: 0, vat_cents: 0, total_cents: 0, notes: MARK)
  t2 = add_lines(inv2, [[RESIN, "16", 1], [RESIN, "17", 1]])
  inv2.update!(subtotal_cents: (t2/1.15).round, vat_cents: (t2 - t2/1.15).round, total_cents: t2, paid_cents: (t2 * 0.4).round, status: "part_paid")
  Payment.create!(billing_account: ba, patient: members.last, amount_cents: (t2 * 0.4).round, method: "eft", received_at: (Date.current - 10).to_time, notes: MARK)
  stats[:invoices] += 2

  # Estimates — different types. Save FIRST, then add lines + recalc.
  e1 = Estimate.create!(patient: head, billing_account: ba, status: "draft", provider_name: CH, subtotal_cents: 0, vat_cents: 0, total_cents: 0, notes: "#{MARK} Crown + filling treatment plan")
  add_lines(e1, [[CROWN, "26", 1], [RESIN, "25", 1]]); e1.recalculate; e1.save!
  e2 = Estimate.create!(patient: head, billing_account: ba, status: "sent", provider_name: EL, subtotal_cents: 0, vat_cents: 0, total_cents: 0, notes: "#{MARK} Extraction")
  add_lines(e2, [[EXTRACT, "38", 1]]); e2.recalculate; e2.save!
  stats[:estimates] += 2
end

puts "[demo] created #{stats[:patients]} patients across #{FAMILIES.size} families, #{stats[:invoices]} invoices, #{stats[:estimates]} estimates"
puts "[demo] accounts: #{BillingAccount.where(%q{account_code LIKE 'DEMO%'}).pluck(:account_code).join(', ')}"
