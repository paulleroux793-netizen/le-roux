# Common SA medical-aid schemes for the New Patient form dropdown. Idempotent.
# Existing imported schemes (~168 plan-specific records) stay as-is; these 10 base names
# give reception a clean picker for new patients. "Other" lets them type any other name.
#   bundle exec rails runner db/seeds/medical_schemes.rb
SCHEMES = %w[
  Discovery
  Bonitas
  Bestmed
  GEMS
  Fedhealth
  Medihelp
  Medshield
  Polmed
  Bankmed
  Profmed
].freeze

created = 0
SCHEMES.each do |name|
  s = MedicalScheme.find_or_initialize_by(name: name)
  s.active = true
  if s.new_record?
    s.save!
    created += 1
  end
end
puts "medical_schemes: #{created} created (#{MedicalScheme.count} total in DB)"
