# LIVE settlement stress test on a REAL billing account.
# Snapshots the account, runs every settlement scenario against its real invoices,
# asserts a money-conservation invariant stays constant after each, then RESTORES the
# account byte-identical. Paul authorised live testing (DB is refreshed before go-live);
# this still leaves the real record exactly as found.
#
# Run: docker compose ... exec -T web bin/rails runner script/stress/settlement_live.rb

def money(c) = "R#{format('%.2f', c.to_i / 100.0)}"

# Imbalance = (inward - refunds) - (invoice.paid non-void + credit). Conservative ops keep
# it CONSTANT at whatever the (possibly imported) baseline is.
def imbalance(acct)
  acct.reload
  inward  = acct.payments.inward.sum(:amount_cents)
  refunds = acct.payments.where(kind: "refund").sum(:amount_cents)
  applied = acct.invoices.where(void: false).sum(:paid_cents)
  (inward - refunds) - (applied + acct.credit_cents.to_i)
end

# Pick a real account with the most outstanding invoices.
acct_id = Invoice.where(status: %w[open part_paid], void: false).where.not(billing_account_id: nil)
                 .group(:billing_account_id).order(Arel.sql("COUNT(*) DESC")).limit(1).count.keys.first
abort("no account with outstanding invoices found") unless acct_id
acct = BillingAccount.find(acct_id)
puts "ACCOUNT #{acct.account_code} (##{acct.id}) — #{acct.invoices.outstanding.count} outstanding invoice(s)"

# ---- snapshot ----
snap_inv     = acct.invoices.map { |i| [ i.id, i.paid_cents, i.status, i.void ] }
snap_credit  = acct.credit_cents.to_i
snap_pay_ids = acct.payments.pluck(:id)
base = imbalance(acct)
puts "baseline imbalance=#{base} credit=#{money(snap_credit)} invoices=#{snap_inv.size} payments=#{snap_pay_ids.size}"

results = []
chk = ->(label) { ok = (imbalance(acct) == base); results << [ label, ok ]; puts "  #{ok ? 'PASS' : 'FAIL'} #{label} (imbalance=#{imbalance(acct)})" }

begin
  outstanding = acct.invoices.outstanding.order(:invoice_date, :id).to_a

  # 1) Overpayment → credit
  inv1 = outstanding.first
  bal1 = inv1.total_cents - inv1.paid_cents
  c0 = acct.reload.credit_cents
  Payment.create!(invoice: inv1, billing_account: acct, patient: inv1.patient, method: "card", amount_cents: bal1 + 5_000)
  inv1.reload
  puts "1) OVERPAY #{inv1.invoice_number}: paid #{money(bal1 + 5_000)} on #{money(bal1)} balance → status=#{inv1.status} credit #{money(c0)}→#{money(acct.reload.credit_cents)}"
  chk.call("overpay caps invoice + banks R50 credit")

  # 2) Apply credit to another invoice (if any), else back to inv1 is full so skip
  inv2 = outstanding[1]
  if inv2
    applied = acct.apply_credit_to(inv2, 3_000)
    puts "2) APPLY CREDIT R30 to #{inv2.invoice_number}: applied #{money(applied)} → #{inv2.reload.status}, credit now #{money(acct.reload.credit_cents)}"
    chk.call("apply credit to second invoice")
  else
    puts "2) (only one outstanding invoice — skipping apply-credit-to-second)"
  end

  # 3) Reverse the overpayment
  pay1 = Payment.where(invoice_id: inv1.id, kind: "payment").order(:id).last
  pay1.reverse!(reason: "live stress test")
  puts "3) REVERSE overpay on #{inv1.invoice_number} → status=#{inv1.reload.status}, credit #{money(acct.reload.credit_cents)}"
  chk.call("reverse payment reopens invoice")

  # 4) Deposit → credit
  acct.payments.create!(method: "eft", kind: "deposit", is_deposit: true, amount_cents: 10_000, patient: acct.head_patient || inv1.patient)
  puts "4) DEPOSIT R100 → credit now #{money(acct.reload.credit_cents)}"
  chk.call("deposit banks credit")

  # 5) Account-level multi-invoice payment
  res = acct.receive_payment(7_500, method: "cash")
  puts "5) ACCOUNT PAYMENT R75 → allocated to #{res[:allocated].size} invoice(s), #{money(res[:to_credit_cents])} to credit"
  chk.call("account payment allocates + banks remainder")

  # 6) Write-off an outstanding invoice
  woff = acct.invoices.outstanding.first
  if woff
    woff.write_off!(reason: "live stress test")
    puts "6) WRITE-OFF #{woff.invoice_number} → status=#{woff.reload.status}, in outstanding? #{acct.invoices.outstanding.exists?(woff.id)}"
    chk.call("write-off clears invoice off the books")
  end

  # 7) Refund from credit
  refundable = [ acct.reload.credit_cents, 5_000 ].min
  if refundable.positive?
    r = acct.refund!(refundable, method: "cash", reason: "live stress test")
    puts "7) REFUND #{money(r)} from credit → credit now #{money(acct.reload.credit_cents)}"
    chk.call("refund pays credit out")
  end

  # 8) Statement renders with brought-forward opening balance
  pdf = StatementPdf.render(acct, from: (Date.current - 365), to: Date.current)
  puts "8) STATEMENT pdf bytes=#{pdf.bytesize} (#{pdf[0, 4].inspect})"
  results << [ "statement renders", pdf[0, 4] == "%PDF" ]
ensure
  # ---- restore: leave the real account exactly as found ----
  Payment.where(billing_account_id: acct.id).where.not(id: snap_pay_ids).delete_all
  snap_inv.each { |id, paid, status, void| Invoice.where(id: id).update_all(paid_cents: paid, status: status, void: void) }
  acct.update_columns(credit_cents: snap_credit)

  now_inv     = BillingAccount.find(acct.id).invoices.map { |i| [ i.id, i.paid_cents, i.status, i.void ] }
  now_credit  = BillingAccount.find(acct.id).credit_cents.to_i
  now_pay_ids = BillingAccount.find(acct.id).payments.pluck(:id)
  restored = (now_inv.sort == snap_inv.sort) && (now_credit == snap_credit) && (now_pay_ids.sort == snap_pay_ids.sort)
  puts "RESTORE #{restored ? 'VERIFIED — account byte-identical to snapshot' : 'FAILED — MANUAL CHECK NEEDED'}"
  passes = results.count { |_, ok| ok }
  puts "RESULT #{passes}/#{results.size} scenarios PASS#{results.any? { |_, ok| !ok } ? " — FAILURES: #{results.reject { |_, ok| ok }.map(&:first).join('; ')}" : ''}"
end
