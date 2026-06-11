total=0; valid=0; bad=0; by_len=Hash.new(0); samples=[]
Patient.where.not(phone: [nil, ""]).find_each do |p|
  total += 1
  digits = p.phone.to_s.gsub(/\D/, "")
  d = digits.sub(/\A27/, "0")                 # +27... -> 0...
  ok = (d.length == 10 && d.start_with?("0"))  # SA national = 10 digits, leading 0
  if ok then valid += 1
  else bad += 1; by_len[digits.length] += 1
    samples << "#{p.id} #{p.full_name}: #{p.phone.inspect} (#{digits.length} digits)" if samples.size < 8
  end
end
puts "[phone] total_with_phone=#{total} valid=#{valid} bad=#{bad} (#{(bad*100.0/[total,1].max).round(1)}%)"
puts "[phone] bad by raw-digit-count: #{by_len.sort.to_h}"
samples.each { |s| puts "  #{s}" }
