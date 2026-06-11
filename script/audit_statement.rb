def r(c) = (c.to_i / 100.0).round(2)
acc = BillingAccount.find_by(account_code: "DEMO001") || BillingAccount.joins(:invoices, :payments).first
billed        = acc.invoices.sum(:total_cents).to_i
payments_tot  = acc.payments.sum(:amount_cents).to_i
invoice_paid  = acc.invoices.sum(:paid_cents).to_i
out_simple    = billed - payments_tot                                   # billed - all payments
out_alloc     = acc.invoices.sum("total_cents - paid_cents").to_i        # sum of per-invoice unpaid
age           = acc.invoices.where(status: %w[open part_paid]).sum("total_cents - paid_cents").to_i
puts "ACCT #{acc.account_code}: billed=#{r billed} payments=#{r payments_tot} invoice_paid_alloc=#{r invoice_paid}"
puts "  outstanding(billed-payments)=#{r out_simple}  outstanding(sum total-paid)=#{r out_alloc}  age-analysis(open/part)=#{r age}"
puts "  RECONCILE: payments==alloc? #{payments_tot==invoice_paid} | out_simple==out_alloc? #{out_simple==out_alloc} | out_alloc==age? #{out_alloc==age}"
# Practice-wide allocation consistency
tb = Invoice.sum(:total_cents).to_i; tp = Payment.sum(:amount_cents).to_i; tip = Invoice.sum(:paid_cents).to_i
puts "PRACTICE: billed=#{r tb} payments=#{r tp} invoice_paid_alloc=#{r tip} | unallocated payments=#{r(tp-tip)}"
puts "  dashboard/AR outstanding(sum total-paid)=#{r(Invoice.where(status: %w[open part_paid]).sum("total_cents - paid_cents"))}"
