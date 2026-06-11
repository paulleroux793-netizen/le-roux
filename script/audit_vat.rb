checked=0; with_lines=0; bad_header=0; bad_lines=0; bad_vat=0; bad_vat15=0
samples=[]
Invoice.includes(:invoice_lines).find_each do |inv|
  checked += 1
  # header: subtotal + vat must equal total
  if inv.subtotal_cents.to_i + inv.vat_cents.to_i != inv.total_cents.to_i
    bad_header += 1; samples << "HDR #{inv.invoice_number}: sub=#{inv.subtotal_cents}+vat=#{inv.vat_cents}!=tot=#{inv.total_cents}" if samples.size < 4
  end
  # VAT must be 15% inclusive: vat == total - round(total/1.15)
  expect_vat = inv.total_cents.to_i - (inv.total_cents.to_i / 1.15).round
  bad_vat15 += 1 if (inv.vat_cents.to_i - expect_vat).abs > 2 && inv.total_cents.to_i > 0
  ls = inv.invoice_lines.to_a
  next if ls.empty?
  with_lines += 1
  lt = ls.sum { |l| l.line_total_cents.to_i }
  if lt != inv.total_cents.to_i
    bad_lines += 1; samples << "LINES #{inv.invoice_number}: sum=#{lt}!=tot=#{inv.total_cents}" if samples.size < 4
  end
  lv = ls.sum { |l| l.vat_cents.to_i }
  bad_vat += 1 if (lv - inv.vat_cents.to_i).abs > 2
end
puts "[vat] checked=#{checked} with_lines=#{with_lines}"
puts "[vat] bad_header(sub+vat!=total)=#{bad_header} | bad_lines(linesum!=total)=#{bad_lines} | bad_line_vat(>2c)=#{bad_vat} | bad_vat15%(>2c)=#{bad_vat15}"
samples.each { |s| puts "  #{s}" }
