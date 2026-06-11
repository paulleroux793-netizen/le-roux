log = []; p = nil; acc = nil
begin
  # 1 ADD PATIENT
  p = Patient.create!(first_name: "Journey", last_name: "Walktest", phone: "+27720009998", notes: "[demo] journey-test", date_of_birth: "1990-05-05")
  acc = BillingAccount.create!(account_code: "JWALK1", billing_name: "Journey Walktest")
  AccountPatient.create!(billing_account: acc, patient: p, relationship: "head"); acc.update!(head_patient_id: p.id)
  log << "1 ADD-PATIENT     : ##{p.id}, account #{acc.account_code} ✓"
  # 2 BOOK
  prov = Provider.active.first
  base = (Date.current + 40).to_time.change(hour: 10)
  appt = Appointment.create!(patient: p, provider: prov, start_time: base, end_time: base + 30*60, status: "scheduled", reason: "Check-up")
  log << "2 BOOK            : appt ##{appt.id} #{appt.start_time.strftime('%-d %b %H:%M')} ✓=#{appt.persisted?}"
  # 3 TREATMENT PLAN + item
  cot = CourseOfTreatment.create!(patient: p, billing_account: acc, setting: "in_chair", status: "planned")
  pc = ProcedureCode.where("default_fee_cents > 0").order(:code).first
  cot.treatment_items.create!(procedure_code: pc, fee_cents: pc.default_fee_cents, tooth_number: "11", status: "planned")
  log << "3 TREATMENT-PLAN  : COT ##{cot.id} items=#{cot.treatment_items.count} est R#{cot.estimated_total} ✓"
  # 4 ESTIMATE + line + provider
  est = Estimate.create!(patient: p, billing_account: acc, status: "draft", subtotal_cents: 0, vat_cents: 0, total_cents: 0, provider_name: "DR CHALITA LE ROUX")
  est.estimate_lines.create!(code: pc.code, description: pc.description, quantity: 1, unit_fee_cents: pc.default_fee_cents, vat_treatment: "standard")
  est.recalculate; est.save!
  log << "4 ESTIMATE        : ##{est.id} lines=#{est.estimate_lines.count} R#{est.total} provider=#{est.provider_name} ✓"
  # 5 PRINT estimate PDF
  pdf = DocumentPdf.estimate(est)
  log << "5 PRINT-ESTIMATE  : #{pdf[0,4] == '%PDF' ? 'valid' : 'BAD'} #{pdf.bytesize}b ✓"
  # 6 CONVERT
  inv = est.accept_and_invoice!
  log << "6 CONVERT→INVOICE : ##{inv.id} provider=#{inv.provider_name} lines=#{inv.invoice_lines.count} R#{inv.total} est=#{est.reload.status} ✓"
  # 7 PAY (half)
  Payment.create!(invoice: inv, billing_account: acc, patient: p, amount_cents: (inv.total_cents / 2), method: "card")
  log << "7 PAY (half)      : invoice status=#{inv.reload.status} balance=R#{inv.balance} ✓"
  # 8 STATEMENT
  st = StatementPdf.render(acc, from: Date.current - 365, to: Date.current)
  log << "8 STATEMENT       : #{st[0,4] == '%PDF' ? 'valid' : 'BAD'} #{st.bytesize}b ✓"
rescue => e
  log << "BROKE: #{e.class}: #{e.message[0,120]}"
ensure
  if p
    Payment.where(patient_id: p.id).delete_all
    Invoice.where(patient_id: p.id).each { |i| i.invoice_lines.delete_all; i.delete }
    Estimate.where(patient_id: p.id).each { |e| e.estimate_lines.delete_all; e.delete }
    CourseOfTreatment.where(patient_id: p.id).each { |c| c.treatment_items.delete_all; c.delete }
    Appointment.where(patient_id: p.id).delete_all
    AccountPatient.where(patient_id: p.id).delete_all
    if acc; BillingAccount.where(id: acc.id).update_all(head_patient_id: nil); BillingAccount.where(id: acc.id).delete_all; end
    Patient.where(id: p.id).delete_all
    log << "CLEANUP          : test patient + records deleted ✓"
  end
end
puts log.join("\n")
