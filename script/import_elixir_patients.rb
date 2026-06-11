# Imports the real Elixir patients (DEPENDANTS, joined to ACCOUNTS) into Ivory as
# Patients + alphabetical A-coded BillingAccounts + AccountPatient links, so the
# patient list organises by account number (A0001, A0002, …). Read-only on Elixir.
#
# Match strategy: by id_number, else by name (non-placeholder), else create.
# Family phone goes to the account head only (phone is unique per patient); other
# members rely on their id_number, or a synthetic id if they have neither.
# Idempotent: re-running matches + updates. Source: tmp/patients.json.
#
# Run on the rig:  bin/rails runner script/import_elixir_patients.rb
require "json"

data = JSON.parse(File.read(ENV.fetch("PATIENTS_JSON", "tmp/patients.json")))
by_acct = data.group_by { |r| r["account_code"] }
stats = Hash.new(0)

def phone_free?(phone, except_id)
  phone.present? && !Patient.where(phone: phone).where.not(id: except_id).exists?
end

by_acct.each do |code, rows|
  next if code.blank?
  head = rows.find { |r| r["is_head"] } || rows.first
  ba = BillingAccount.find_or_initialize_by(account_code: code)
  ba.billing_name = "#{head['first_name']} #{head['account_surname']}".strip if ba.billing_name.blank?
  ba.email = rows.map { |r| r["email"] }.compact.first if ba.email.blank?
  ba.save!

  rows.each_with_index do |r, i|
    begin
      pt = (Patient.find_by(id_number: r["id_number"]) if r["id_number"].present?)
      pt ||= Patient.where("LOWER(first_name)=? AND LOWER(last_name)=?", r["first_name"].downcase, r["last_name"].downcase)
                    .where("notes IS NULL OR notes NOT LIKE ?", "%[elixir-test]%").first
      pt ||= Patient.new
      new_record = pt.new_record?

      pt.first_name = r["first_name"]
      pt.last_name  = r["last_name"]
      pt.date_of_birth = (Date.parse(r["date_of_birth"]) rescue nil) if r["date_of_birth"]
      pt.email = r["email"] if r["email"].present? && pt.email.blank?
      pt.id_number = r["id_number"] if r["id_number"].present?
      # Phone: only the head carries the (shared) family number, and only if free.
      if r["is_head"] && phone_free?(r["phone"], pt.id)
        pt.phone = r["phone"]
      end
      # Every patient needs phone OR id_number.
      if pt.id_number.blank? && pt.phone.blank?
        pt.id_number = "ELX-#{code}-#{i}"
      end
      begin
        pt.save!
      rescue ActiveRecord::RecordInvalid => e
        raise unless e.message.include?("Phone")  # shared family number collided
        pt.phone = nil
        pt.id_number = "ELX-#{code}-#{i}" if pt.id_number.blank?
        pt.save!
      end
      stats[new_record ? :created : :matched] += 1

      # Make the A-coded account the patient's primary: drop other links, add this.
      pt.account_patients.where.not(billing_account_id: ba.id).destroy_all
      ap = AccountPatient.find_or_initialize_by(patient_id: pt.id, billing_account_id: ba.id)
      ap.relationship = r["is_head"] ? "head" : "dependant"  # AccountPatient::RELATIONSHIPS
      ap.save!
      ba.update!(head_patient_id: pt.id) if r["is_head"] && ba.head_patient_id.blank?
    rescue => e
      stats[:errors] += 1
      Rails.logger.warn("[patients] skip #{r['first_name']} #{r['last_name']}: #{e.class}: #{e.message}")
    end
  end
end

acoded = BillingAccount.where("account_code ~ ?", '^[A-Z][0-9]{4}$').count
puts "[patients] matched=#{stats[:matched]} created=#{stats[:created]} errors=#{stats[:errors]}"
puts "[patients] A-coded accounts=#{acoded} · total Patient=#{Patient.count} · BillingAccount=#{BillingAccount.count}"
