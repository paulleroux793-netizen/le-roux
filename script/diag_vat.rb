def r(c) = (c.to_i/100.0).round(2)
Invoice.includes(:invoice_lines).where("total_cents > 0").limit(3).each do |inv|
  ls = inv.invoice_lines.to_a
  puts "INV #{inv.invoice_number}: header sub=#{r inv.subtotal_cents} vat=#{r inv.vat_cents} tot=#{r inv.total_cents}"
  puts "  lines: #{ls.size}, line_vat_sum=#{r(ls.sum{|l| l.vat_cents.to_i})}, line_total_sum=#{r(ls.sum{|l| l.line_total_cents.to_i})}"
  l = ls.first
  puts "  sample line: code=#{l.code} qty=#{l.quantity} unit_fee=#{r l.unit_fee_cents} line_total=#{r l.line_total_cents} vat=#{l.vat_cents.inspect} vat_treatment=#{l.vat_treatment.inspect}" if l
end
# how many lines have nil/zero vat_cents?
total_lines = InvoiceLine.count
zero_vat = InvoiceLine.where("vat_cents IS NULL OR vat_cents = 0").count
puts "[diag] invoice_lines total=#{total_lines} with nil/zero vat_cents=#{zero_vat}"
