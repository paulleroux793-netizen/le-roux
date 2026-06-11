# Only the UNAMBIGUOUS case: +27 followed by a full national 0XXXXXXXXX (the leading
# 0 wasn't dropped). Correct E.164 = +27 + the 9 digits after the 0. Skip if it would
# collide with another patient's phone. Nothing else is touched.
fixed=[]; skipped=[]
Patient.where("phone LIKE '+270%'").find_each do |p|
  d = p.phone.to_s.gsub(/\D/, "")
  next unless d =~ /\A270(\d{9})\z/
  np = "+27#{$1}"
  if Patient.where.not(id: p.id).where(phone: np).exists?
    skipped << "#{p.full_name}: #{p.phone} -> #{np} (DUP, skipped)"
  else
    p.update_column(:phone, np); fixed << "#{p.full_name}: -> #{np}"
  end
end
puts "[phonefix] fixed=#{fixed.size} skipped_dup=#{skipped.size}"
(fixed+skipped).each { |x| puts "  #{x}" }
