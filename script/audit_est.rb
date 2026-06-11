checked=0; with_lines=0; hdr_only=0; bad_lined_hdr=0; bad_lines=0; hdr_only_zero=0; samples=[]
Estimate.includes(:estimate_lines).find_each do |e|
  checked += 1
  ls = e.estimate_lines.to_a
  if ls.empty?
    hdr_only += 1; hdr_only_zero += 1 if e.total_cents.to_i <= 0
  else
    with_lines += 1
    if e.subtotal_cents.to_i + e.vat_cents.to_i != e.total_cents.to_i
      bad_lined_hdr += 1; samples << "HDR #{e.estimate_number}: #{e.subtotal_cents}+#{e.vat_cents}!=#{e.total_cents}" if samples.size<3
    end
    lt = ls.sum { |l| l.line_total_cents.to_i }
    if lt != e.total_cents.to_i
      bad_lines += 1; samples << "LINES #{e.estimate_number}: #{lt}!=#{e.total_cents}" if samples.size<3
    end
  end
end
puts "[est] checked=#{checked} with_lines=#{with_lines} header_only=#{hdr_only}"
puts "[est] (lined) bad_sub+vat!=total=#{bad_lined_hdr} | bad_linesum!=total=#{bad_lines}"
puts "[est] (header-only) zero/neg total=#{hdr_only_zero}"
samples.each { |s| puts "  #{s}" }
