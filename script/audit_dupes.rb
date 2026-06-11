# id_number = strongest (unique person). name+dob = likely. phone = often family (weak).
begin
  idd = Patient.where.not(id_number: [nil,""]).group(:id_number).count.select { |k,v| v>1 }
  puts "[dup] id_number: #{idd.size} groups, #{idd.values.sum} patients (STRONG signal = true dupes)"
  idd.first(4).each { |k,n| ns = Patient.where(id_number: k).pluck(:id,:first_name,:last_name).map{|i,f,l| "##{i} #{f} #{l}"}; puts "  x#{n}: #{ns.join(' | ')}" }
rescue => e
  puts "[dup] id_number: skipped (#{e.class}: #{e.message[0,50]})"
end
nd = Patient.where.not(date_of_birth: nil).group(:first_name, :last_name, :date_of_birth).count.select { |k,v| v>1 }
puts "[dup] name+dob: #{nd.size} groups, #{nd.values.sum} patients (likely dupes)"
nd.first(4).each { |k,n| puts "  #{k[0]} #{k[1]} / #{k[2]} x#{n}" }
ph = Patient.where.not(phone: [nil,""]).group(:phone).count.select { |k,v| v>1 }
puts "[dup] phone: #{ph.size} numbers shared, #{ph.values.sum} patients (WEAK = often family members)"
