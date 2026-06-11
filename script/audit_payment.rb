ActiveRecord::Base.transaction do
  acc = BillingAccount.joins(:patients).first
  pt  = acc.patients.first
  mk  = -> { Invoice.create!(billing_account: acc, patient: pt, invoice_date: Date.current, subtotal_cents: 8696, vat_cents: 1304, total_cents: 10000, status: "open") }
  inv = mk.call
  puts "START: status=#{inv.status} paid=#{inv.paid_cents} balance=#{inv.balance}"
  Payment.create!(invoice: inv, billing_account: acc, patient: pt, amount_cents: 4000, method: "cash")
  inv.reload; puts "PARTIAL R40: status=#{inv.status} paid=#{inv.paid_cents} balance=#{inv.balance}  EXPECT part_paid/4000/60.0  -> #{inv.status=='part_paid' && inv.paid_cents==4000 && inv.balance==60.0}"
  Payment.create!(invoice: inv, billing_account: acc, patient: pt, amount_cents: 6000, method: "card")
  inv.reload; puts "FULL +R60: status=#{inv.status} paid=#{inv.paid_cents} balance=#{inv.balance}  EXPECT paid/10000/0.0  -> #{inv.status=='paid' && inv.paid_cents==10000 && inv.balance==0.0}"
  inv2 = mk.call
  Payment.create!(invoice: inv2, billing_account: acc, patient: pt, amount_cents: 12000, method: "eft")
  inv2.reload; puts "OVERPAY R120/R100: status=#{inv2.status} paid=#{inv2.paid_cents} balance=#{inv2.balance}  EXPECT paid/12000/-20.0  -> #{inv2.status=='paid' && inv2.paid_cents==12000 && inv2.balance==-20.0}"
  raise ActiveRecord::Rollback
end
puts "[audit] rolled back — no test data persisted"
