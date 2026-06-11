# READ-ONLY live data-integrity sweep. Finds real money/state issues across the whole DB
# (no mutations). Run: docker compose ... exec -T web bin/rails runner script/stress/live_audit.rb
def line(label, n, sample = nil)
  flag = n.positive? ? "⚠️" : "ok"
  puts "#{flag} #{label}: #{n}#{sample && n.positive? ? "  e.g. #{sample}" : ''}"
end

# 1) Invoices over-paid beyond their total (legacy overpayments not banked as credit)
over = Invoice.where("paid_cents > total_cents")
line("invoices paid_cents > total_cents (legacy overpay)", over.count, over.limit(5).pluck(:invoice_number))

# 2) Status inconsistencies
paid_not_full = Invoice.where(status: "paid").where("paid_cents < total_cents").where(void: false)
line("status=paid but not fully paid", paid_not_full.count, paid_not_full.limit(5).pluck(:invoice_number))
open_but_paid = Invoice.where(status: "open").where("paid_cents > 0").where(void: false)
line("status=open but has payments", open_but_paid.count, open_but_paid.limit(5).pluck(:invoice_number))
partpaid_full = Invoice.where(status: "part_paid").where("paid_cents >= total_cents").where("total_cents > 0")
line("status=part_paid but fully paid", partpaid_full.count, partpaid_full.limit(5).pluck(:invoice_number))

# 3) void / status mismatch
void_mismatch = Invoice.where(void: true).where.not(status: "void")
line("void=true but status != void", void_mismatch.count, void_mismatch.limit(5).pluck(:invoice_number))
status_void_mismatch = Invoice.where(status: "void").where(void: false)
line("status=void but void=false", status_void_mismatch.count, status_void_mismatch.limit(5).pluck(:invoice_number))

# 4) Negative money
line("invoices with negative paid_cents", Invoice.where("paid_cents < 0").count)
line("invoices with negative total_cents", Invoice.where("total_cents < 0").count)
line("accounts with negative credit_cents", BillingAccount.where("credit_cents < 0").count)
line("payments with non-positive amount", Payment.where("amount_cents <= 0").count)

# 5) Orphan payments (no invoice AND no account)
orphan = Payment.where(invoice_id: nil, billing_account_id: nil)
line("payments with no invoice and no account", orphan.count, orphan.limit(5).pluck(:id))

# 6) Invoices whose lines don't sum to the header total (rounding/recalc drift)
drift = 0; drift_eg = []
Invoice.where(void: false).includes(:invoice_lines).find_each(batch_size: 500) do |inv|
  next if inv.invoice_lines.empty?
  s = inv.invoice_lines.sum { |l| l.line_total_cents.to_i }
  if s != inv.total_cents.to_i
    drift += 1; drift_eg << inv.invoice_number if drift_eg.size < 5
  end
end
line("invoices whose lines != header total", drift, drift_eg)

# 7) Appointment double-bookings (same provider, overlapping, not cancelled)
dbl = 0; dbl_eg = []
appts = Appointment.where.not(status: :cancelled).where.not(provider_id: nil)
                   .where("start_time > ?", 30.days.ago).order(:provider_id, :start_time)
                   .pluck(:id, :provider_id, :start_time, :end_time)
appts.group_by { |a| a[1] }.each do |_prov, list|
  list.each_cons(2) do |a, b|
    if b[2] && a[3] && b[2] < a[3] # next start < prev end
      dbl += 1; dbl_eg << [ a[0], b[0] ] if dbl_eg.size < 5
    end
  end
end
line("overlapping appointments (same provider, 30d)", dbl, dbl_eg)

# 8) Treatment items referencing a missing procedure code
ti_bad = TreatmentItem.where.not(procedure_code_id: nil).where.missing(:procedure_code)
line("treatment_items with missing procedure_code", ti_bad.count)

puts "AUDIT DONE"
