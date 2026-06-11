def enc?(v) = v.to_s.include?('"p":') || v.to_s.include?('{"p"')
fs = ActiveRecord::Base.connection.select_value("SELECT data FROM form_submissions WHERE data IS NOT NULL AND data <> '' LIMIT 1")
puts "form_submissions.data raw: #{fs.to_s[0,55]}  encrypted=#{enc?(fs)}"
idn = ActiveRecord::Base.connection.select_value("SELECT id_number FROM patients WHERE id_number IS NOT NULL AND id_number <> '' LIMIT 1")
puts "patients.id_number raw:    #{idn.to_s[0,55]}  encrypted=#{enc?(idn)}"
alg = ActiveRecord::Base.connection.select_value("SELECT allergies FROM patient_medical_histories WHERE allergies IS NOT NULL AND allergies <> '' LIMIT 1")
puts "med_histories.allergies raw: #{alg.to_s[0,40]}  encrypted=#{enc?(alg)}"
# plaintext stragglers
plain_id = ActiveRecord::Base.connection.select_value("SELECT COUNT(*) FROM patients WHERE id_number ~ '^[0-9]{13}$'")
plain_fs = ActiveRecord::Base.connection.select_value("SELECT COUNT(*) FROM form_submissions WHERE data LIKE '{%' AND data NOT LIKE '%\"p\":%'")
puts "[phi] plaintext 13-digit id_numbers=#{plain_id} | plaintext-looking form_submissions=#{plain_fs}"
