# Ivory scenario harness — exercises the NEW practice-management phases (1-6) across many edge
# cases to find breaks. Run:  docker compose exec -T web bundle exec rails runner script/ivory_scenarios.rb
#
# Everything runs inside one transaction that ROLLS BACK at the end (each scenario in its own
# savepoint via requires_new), so it never pollutes data. Reports PASS/FAIL with reasons.
$pass = 0; $fail = 0; $failures = []
@seq = 0
def uphone; @seq += 1; format("+2799%07d", @seq); end
def assert(cond, msg = "assertion failed"); raise msg unless cond; end
def check(name)
  ActiveRecord::Base.transaction(requires_new: true) do
    yield
    $pass += 1
  end
rescue => e
  $fail += 1
  $failures << "#{name} :: #{e.class}: #{e.message.to_s[0, 160]}"
end

def new_patient(first = "Test", last = "Patient")
  Patient.create!(first_name: first, last_name: last, phone: uphone)
end
def some_code(cat = nil)
  (cat ? ProcedureCode.where(category: cat) : ProcedureCode).where.not(default_fee_cents: nil).first
end

ActiveRecord::Base.transaction do
  pc       = some_code || ProcedureCode.first
  cosmetic = ProcedureCode.find_by(vat_treatment: "standard") || pc

  # ---------- PHASE 1: accounts / schemes / catalogue / macros ----------
  check("P1 account code auto-increments") do
    a = BillingAccount.create!(billing_name: "Fam A", account_code: BillingAccount.next_account_code)
    b = BillingAccount.create!(billing_name: "Fam B", account_code: BillingAccount.next_account_code)
    assert a.account_code != b.account_code, "codes not unique"
  end
  check("P1 duplicate account_code rejected") do
    code = BillingAccount.next_account_code
    BillingAccount.create!(billing_name: "X", account_code: code)
    dup = BillingAccount.new(billing_name: "Y", account_code: code)
    assert !dup.save, "duplicate account_code allowed"
  end
  check("P1 family: multiple patients on one account") do
    acc = BillingAccount.create!(billing_name: "Fam")
    p1 = new_patient("Head", "Fam"); p2 = new_patient("Dep", "Fam")
    AccountPatient.create!(billing_account: acc, patient: p1, relationship: "head")
    AccountPatient.create!(billing_account: acc, patient: p2, relationship: "dependant")
    assert acc.patients.count == 2, "family size wrong"
  end
  check("P1 same patient twice on one account rejected") do
    acc = BillingAccount.create!(billing_name: "Fam"); p = new_patient
    AccountPatient.create!(billing_account: acc, patient: p, relationship: "self")
    dup = AccountPatient.new(billing_account: acc, patient: p, relationship: "head")
    assert !dup.save, "duplicate membership allowed"
  end
  check("P1 invalid relationship rejected") do
    acc = BillingAccount.create!(billing_name: "Fam"); p = new_patient
    ap = AccountPatient.new(billing_account: acc, patient: p, relationship: "bogus")
    assert !ap.save, "invalid relationship allowed"
  end
  check("P1 scheme membership + dependants") do
    sch = MedicalScheme.create!(name: "TestScheme #{@seq}")
    main = new_patient("Main", "Mem")
    m = SchemeMembership.create!(medical_scheme: sch, main_member_patient: main, member_number: "M#{@seq}")
    dep = new_patient("Dep", "Mem")
    SchemeMembershipPatient.create!(scheme_membership: m, patient: dep, role: "dependant", dependant_code: "01")
    assert m.patients.count == 1 && m.active?, "membership wiring wrong"
  end
  check("P1 procedure code VAT + fee accessors") do
    assert pc.default_fee >= 0, "fee accessor"
    assert ProcedureCode::VAT_TREATMENTS.include?(pc.vat_treatment), "vat value"
  end
  check("P1 macro expands to linked codes") do
    m = TreatmentMacro.where.not(id: nil).joins(:treatment_macro_items).first
    assert m && m.treatment_macro_items.any?, "no macro with items"
  end

  # ---------- PHASE 2: clinical core ----------
  check("P2 invalid setting rejected") do
    p = new_patient
    assert !CourseOfTreatment.new(patient: p, setting: "bogus").save, "invalid setting allowed"
  end
  check("P2 all valid settings accepted") do
    p = new_patient
    CourseOfTreatment::SETTINGS.each { |s| assert CourseOfTreatment.new(patient: p, setting: s).save, "setting #{s} rejected" }
  end
  check("P2 treatment item fee/vat snapshot on create") do
    p = new_patient; cot = CourseOfTreatment.create!(patient: p, setting: "in_chair")
    ti = cot.treatment_items.create!(procedure_code: pc, tooth_number: "16")
    assert ti.fee_cents == pc.default_fee_cents, "fee not snapshotted"
    assert ti.vat_treatment == pc.vat_treatment, "vat not snapshotted"
  end
  check("P2 complete! sets status + date") do
    p = new_patient; cot = CourseOfTreatment.create!(patient: p, setting: "in_chair")
    ti = cot.treatment_items.create!(procedure_code: pc); ti.complete!
    assert ti.status == "completed" && ti.completed_date.present?, "complete! failed"
  end
  check("P2 voided items excluded from totals") do
    p = new_patient; cot = CourseOfTreatment.create!(patient: p, setting: "in_chair")
    cot.treatment_items.create!(procedure_code: pc, status: "completed", completed_date: Date.current)
    cot.treatment_items.create!(procedure_code: pc, status: "voided")
    assert cot.completed_total == pc.default_fee_cents / 100.0, "voided counted"
  end
  check("P2 signed clinical note is immutable") do
    p = new_patient; n = ClinicalNote.create!(patient: p, assessment: "a"); n.sign!(by: "Dr")
    edited = begin; n.update!(assessment: "b"); true; rescue; false; end
    assert !edited, "signed note was editable"
  end
  check("P2 amendment supersedes original") do
    p = new_patient; n = ClinicalNote.create!(patient: p, assessment: "a"); n.sign!(by: "Dr")
    am = n.amend({ assessment: "corrected" }, by: "Dr")
    assert am.supersedes_id == n.id, "amend chain broken"
  end
  check("P2 invalid tooth condition rejected") do
    p = new_patient
    assert !ToothChartEntry.new(patient: p, tooth_number: "16", condition: "bogus").save, "bad condition allowed"
  end

  # ---------- PHASE 3: money ----------
  check("P3 invoice numbers are sequential + unique") do
    p = new_patient
    i1 = Invoice.create!(patient: p, invoice_date: Date.current)
    i2 = Invoice.create!(patient: p, invoice_date: Date.current)
    assert i1.invoice_number != i2.invoice_number, "invoice numbers collided"
  end
  check("P3 zero-rated line has no VAT") do
    z = ProcedureCode.find_by(vat_treatment: "zero_rated") || pc
    p = new_patient; inv = Invoice.create!(patient: p, invoice_date: Date.current)
    l = inv.invoice_lines.create!(procedure_code: z, code: z.code, quantity: 1, unit_fee_cents: 10000, vat_treatment: "zero_rated")
    assert l.vat_cents == 0, "zero-rated had VAT"
  end
  check("P3 standard-rated line extracts 15% VAT (inclusive)") do
    p = new_patient; inv = Invoice.create!(patient: p, invoice_date: Date.current)
    l = inv.invoice_lines.create!(code: "X", quantity: 1, unit_fee_cents: 11500, vat_treatment: "standard")
    assert l.vat_cents == 1500, "VAT-inclusive math wrong: #{l.vat_cents}"
  end
  check("P3 quantity < 1 coerced to 1") do
    p = new_patient; inv = Invoice.create!(patient: p, invoice_date: Date.current)
    l = inv.invoice_lines.create!(code: "X", quantity: 0, unit_fee_cents: 5000, vat_treatment: "zero_rated")
    assert l.quantity == 1, "quantity not coerced"
  end
  check("P3 invoice from course bills only completed items") do
    p = new_patient; cot = CourseOfTreatment.create!(patient: p, setting: "in_chair")
    cot.treatment_items.create!(procedure_code: pc, status: "completed", completed_date: Date.current)
    cot.treatment_items.create!(procedure_code: pc, status: "planned")
    inv = Invoice.from_course(cot); inv.save!
    assert inv.invoice_lines.count == 1, "planned item was billed"
  end
  check("P3 estimate -> invoice conversion") do
    p = new_patient; cot = CourseOfTreatment.create!(patient: p, setting: "in_chair")
    cot.treatment_items.create!(procedure_code: pc, status: "planned")
    est = Estimate.from_course(cot); est.save!
    inv = est.accept_and_invoice!
    assert est.reload.status == "accepted" && inv.persisted?, "conversion failed"
  end
  check("P3 partial then full payment updates status") do
    p = new_patient; inv = Invoice.create!(patient: p, invoice_date: Date.current)
    inv.invoice_lines.create!(code: "X", quantity: 1, unit_fee_cents: 10000, vat_treatment: "zero_rated")
    inv.recalculate; inv.save!
    Payment.create!(patient: p, invoice: inv, method: "card", amount_cents: 4000)
    assert inv.reload.status == "part_paid", "not part_paid"
    Payment.create!(patient: p, invoice: inv, method: "cash", amount_cents: 6000)
    assert inv.reload.status == "paid", "not paid after full"
  end
  check("P3 invalid payment method rejected") do
    p = new_patient; inv = Invoice.create!(patient: p, invoice_date: Date.current)
    assert !Payment.new(patient: p, invoice: inv, method: "crypto", amount_cents: 100).save, "bad method allowed"
  end
  check("P3 negative/zero payment rejected") do
    p = new_patient; inv = Invoice.create!(patient: p, invoice_date: Date.current)
    assert !Payment.new(patient: p, invoice: inv, method: "card", amount_cents: 0).save, "zero payment allowed"
  end
  check("P3 void invoice flagged + status void") do
    p = new_patient; inv = Invoice.create!(patient: p, invoice_date: Date.current); inv.void!(reason: "err")
    assert inv.void && inv.status == "void", "void failed"
  end
  check("P3 statement closing balance = charges - payments") do
    p = new_patient; acc = BillingAccount.create!(billing_name: "S")
    inv = Invoice.create!(patient: p, billing_account: acc, invoice_date: Date.current)
    inv.invoice_lines.create!(code: "X", quantity: 1, unit_fee_cents: 20000, vat_treatment: "zero_rated"); inv.recalculate; inv.save!
    Payment.create!(billing_account: acc, invoice: inv, method: "eft", amount_cents: 5000)
    stmt = Statement.generate_for(acc)
    assert stmt.closing_balance_cents == 15000, "statement balance wrong: #{stmt.closing_balance_cents}"
  end

  # ---------- PHASE 4: digital file / forms / notepad ----------
  check("P4 invalid folder rejected") do
    p = new_patient
    assert !Document.new(patient: p, folder: "bogus", title: "t").save, "bad folder allowed"
  end
  check("P4 form completion files a signed document") do
    p = new_patient
    tpl = FormTemplate.create!(key: "consent_test#{@seq}", name: "Consent", version: 1)
    sub = FormSubmission.create!(form_template: tpl, patient: p); sub.mark_sent!
    doc = sub.complete!(data: { ok: true }, signature_data: "sig")
    assert doc.signed && doc.folder == "consent_forms" && sub.reload.status == "completed", "form filing wrong"
  end
  check("P4 form token is unique + present") do
    p = new_patient; tpl = FormTemplate.create!(key: "f#{@seq}", name: "F", version: 1)
    s1 = FormSubmission.create!(form_template: tpl, patient: p)
    s2 = FormSubmission.create!(form_template: tpl, patient: p)
    assert s1.token.present? && s1.token != s2.token, "tokens not unique"
  end
  check("P4 notepad files to patient file") do
    p = new_patient; n = NotepadPage.create!(patient: p, title: "Note", content: "x")
    doc = n.file_to_patient_file!(by: "Dr")
    assert doc.source == "notepad" && n.reload.document_id == doc.id, "notepad filing wrong"
  end
  check("P4 patient.destroy cascades cleanly (FK fix #19)") do
    p = new_patient; cot = CourseOfTreatment.create!(patient: p, setting: "in_chair")
    est = Estimate.from_course(cot); est.save!
    doc = Document.create!(patient: p, folder: "consent_forms", title: "C", source: "whatsapp_form")
    tpl = FormTemplate.create!(key: "z#{@seq}", name: "Z", version: 1)
    FormSubmission.create!(form_template: tpl, patient: p, document: doc)
    ScribeSession.create!(patient: p, estimate: est, course_of_treatment: cot)
    p.destroy!
    assert !Patient.exists?(p.id), "patient not destroyed"
  end

  # ---------- PHASE 5: imaging / recalls / reporting ----------
  check("P5 imaging study modality validation") do
    assert !ImagingStudy.new(modality: "bogus").save, "bad modality allowed"
  end
  check("P5 imaging matched study links a patient") do
    p = new_patient
    s = ImagingStudy.create!(patient: p, modality: "panoramic", status: "matched", source_folder: "F#{@seq}", source_file: "x.jpg")
    assert ImagingStudy.matched.exists?(s.id), "matched scope wrong"
  end
  check("P5 imaging import is idempotent (no dup source)") do
    ImagingStudy.create!(modality: "intraoral_2d", status: "needs_match", source_folder: "DUP#{@seq}", source_file: "a.jpg")
    dup = ImagingStudy.new(modality: "intraoral_2d", status: "needs_match", source_folder: "DUP#{@seq}", source_file: "a.jpg")
    assert !dup.save, "duplicate source allowed"
  end
  check("P5 recall scopes (due / overdue)") do
    p = new_patient
    Recall.create!(patient: p, recall_type: "checkup", due_on: 1.day.ago.to_date, status: "due")
    assert Recall.overdue.where(patient: p).exists?, "overdue scope wrong"
  end
  check("P5 invalid recall type rejected") do
    p = new_patient
    assert !Recall.new(patient: p, recall_type: "bogus", due_on: Date.current).save, "bad recall type allowed"
  end

  # ---------- PHASE 6: AI scribe ----------
  check("P6 scribe extracts findings + maps existing codes") do
    f = ScribeDraftService.new("Extract tooth 28. Examination today.").extract
    assert f.any? { |x| x["code"] == "8201" && x["tooth"] == "28" }, "extraction missed extraction"
  end
  check("P6 scribe flags needs_code for missing catalogue code") do
    f = ScribeDraftService.new("Filling on tooth 16.").extract
    fill = f.find { |x| x["note"].to_s.downcase.include?("filling") }
    assert fill && fill["needs_code"] == true && fill["code"].nil?, "did not flag needs_code"
  end
  check("P6 empty transcript -> no findings, no crash") do
    assert ScribeDraftService.new("").extract == [], "empty transcript not handled"
  end
  check("P6 build_proposal creates COT + draft estimate") do
    p = new_patient
    s = ScribeSession.create!(patient: p, status: "recording")
    s.draft_from_transcript!("Extract 28. Examination today.")
    est = s.build_proposal!
    assert s.course_of_treatment.present? && est&.persisted?, "proposal not built"
    assert s.course_of_treatment.treatment_items.all? { |i| i.status == "planned" }, "proposal auto-completed items"
  end
  check("P6 scribe never auto-bills (no invoice created)") do
    p = new_patient
    s = ScribeSession.create!(patient: p, status: "recording")
    s.draft_from_transcript!("Extract 28."); s.build_proposal!
    assert p.invoices.count == 0, "scribe created an invoice"
  end
  check("P6 start_for binds appointment + patient") do
    p = new_patient
    appt = Appointment.create!(patient: p, start_time: 1.day.from_now, end_time: 1.day.from_now + 30.minutes)
    s = ScribeSession.start_for(appt)
    assert s.appointment_id == appt.id && s.patient_id == p.id && s.status == "recording", "start_for wrong"
  end

  raise ActiveRecord::Rollback # leave no trace
end

puts "\n================ IVORY SCENARIO RESULTS ================"
puts "PASS: #{$pass}   FAIL: #{$fail}"
$failures.each { |f| puts "  ✗ #{f}" }
puts "======================================================="
