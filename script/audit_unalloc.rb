def r(c) = (c.to_i/100.0).round(2)
credit_accts = 0; credit_total = 0; affected = 0
BillingAccount.find_each do |a|
  pay = a.payments.sum(:amount_cents).to_i
  alloc = a.invoices.sum(:paid_cents).to_i
  diff = pay - alloc
  next if diff <= 0
  affected += 1; credit_total += diff
end
puts "[audit] accounts with unallocated payments: #{affected} | total unallocated: R#{r credit_total}"
# Is it import-era? sample 3 affected accounts
shown = 0
BillingAccount.find_each do |a|
  next if shown >= 3
  pay = a.payments.sum(:amount_cents).to_i; alloc = a.invoices.sum(:paid_cents).to_i
  next if pay - alloc <= 0
  puts "  #{a.account_code}: payments=R#{r pay} allocated=R#{r alloc} unallocated=R#{r(pay-alloc)} invoices=#{a.invoices.count}"
  shown += 1
end
