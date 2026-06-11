# DEEP STRESS TEST (safe — transaction ALWAYS rolled back): Invoice#register_payment!
# lifecycle + the two hardening guards (non-positive ignored; voided invoice can't be paid).
# Run: bin/rails runner script/stress/invoice_payment_guards.rb
p = Patient.find(2985)
r = {}
begin
  ActiveRecord::Base.transaction do
    inv = Invoice.create!(patient: p, billing_account: p.billing_accounts.first,
                          status: "open", total_cents: 50_000, paid_cents: 0,
                          vat_cents: 0, subtotal_cents: 50_000)
    inv.register_payment!(20_000)                              # partial → part_paid
    r[:partial] = "#{inv.paid_cents}/#{inv.status}"

    before = [ inv.paid_cents, inv.status ]
    inv.register_payment!(-500); inv.register_payment!(0)      # non-positive → ignored
    r[:nonpos_ignored] = ([ inv.paid_cents, inv.status ] == before)

    inv.register_payment!(30_000)                              # complete → paid
    r[:full] = "#{inv.paid_cents}/#{inv.status}"

    inv.void!                                                  # cancel
    bvoid = [ inv.paid_cents, inv.status ]
    inv.register_payment!(10_000)                              # void → must be blocked
    r[:void_blocked] = ([ inv.paid_cents, inv.status ] == bvoid && inv.status == "void")
    raise ActiveRecord::Rollback
  end
  ok = r[:partial] == "20000/part_paid" && r[:nonpos_ignored] == true &&
       r[:full] == "50000/paid" && r[:void_blocked] == true
  puts "invoice_guards: partial=#{r[:partial]} nonpos_ignored=#{r[:nonpos_ignored]} full=#{r[:full]} void_blocked=#{r[:void_blocked]} => #{ok ? 'PASS' : 'FAIL'}"
rescue => e
  puts "ERROR: #{e.class}: #{e.message}"
end
puts "POST-CHECK demo-2985 invoices=#{Invoice.where(patient_id: 2985).count} (rolled back; nothing new should persist)"
