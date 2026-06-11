# One-off backfill: re-encrypt PHI that was written BEFORE `encrypts` was added to
# the models. Safe to run more than once. Requires support_unencrypted_data = true
# (the rollout default) so plaintext rows can still be read while being rewritten.
#
#   bin/rails phi:encrypt    # rewrite every PHI row through the encrypting type
#   bin/rails phi:verify     # report how many rows still look like plaintext
#
# After `phi:encrypt` succeeds in production, set AR_ENCRYPTION_SUPPORT_UNENCRYPTED=false.
namespace :phi do
  # Forcing each encrypted attribute "dirty" makes save! rewrite it through the
  # encrypting serializer, turning the existing plaintext into ciphertext.
  reencrypt = lambda do |scope, attrs|
    count = 0
    scope.find_each(batch_size: 200) do |record|
      attrs.each { |a| record.public_send("#{a}_will_change!") }
      record.save!(validate: false)
      count += 1
    end
    count
  end

  desc "Re-encrypt existing plaintext PHI in place (patients, medical histories, form submissions)"
  task encrypt: :environment do
    unless ActiveRecord::Encryption.config.support_unencrypted_data
      abort "Refusing to run: support_unencrypted_data is OFF. Set AR_ENCRYPTION_SUPPORT_UNENCRYPTED=true first."
    end

    patients = reencrypt.call(Patient.where.not(id_number: [nil, ""]), %i[id_number])
    puts "patients.id_number re-encrypted: #{patients}"

    histories = reencrypt.call(
      PatientMedicalHistory.all,
      %i[allergies chronic_conditions current_medications dental_notes
         emergency_contact_name emergency_contact_phone insurance_policy_number]
    )
    puts "patient_medical_histories re-encrypted: #{histories}"

    forms = reencrypt.call(FormSubmission.where.not(data: nil), %i[data signature_data])
    puts "form_submissions re-encrypted: #{forms}"

    # Mail PHI (added 2026-06-04): patient emails carry health info.
    mail_msgs = reencrypt.call(MailMessage.all, %i[body_text body_html subject snippet])
    puts "mail_messages re-encrypted: #{mail_msgs}"

    mail_threads = reencrypt.call(MailThread.all, %i[subject])
    puts "mail_threads re-encrypted: #{mail_threads}"

    # Scribe transcripts/notes (most-sensitive; usually 0 rows early on).
    scribe = reencrypt.call(ScribeSession.all, %i[transcript notes])
    puts "scribe_sessions re-encrypted: #{scribe}"

    puts "Done. Verify with `bin/rails phi:verify`, then set AR_ENCRYPTION_SUPPORT_UNENCRYPTED=false."
  end

  desc "Report rows whose PHI still appears to be unencrypted (raw DB inspection)"
  task verify: :environment do
    # Ciphertext is Base64/JSON envelope; plaintext SA IDs are 13 digits. A row whose
    # raw column still matches a plain pattern hasn't been backfilled.
    plain_ids = Patient.where.not(id_number: nil)
                       .where("id_number ~ '^[0-9]{6,13}$'").count
    puts "patients with plaintext-looking id_number: #{plain_ids}"

    plain_data = ActiveRecord::Base.connection.select_value(
      "SELECT COUNT(*) FROM form_submissions WHERE data IS NOT NULL AND left(data, 1) IN ('{', '[')"
    )
    puts "form_submissions with plaintext-looking JSON data: #{plain_data}"

    # Encrypted columns hold a JSON envelope like {"p":"...","h":{...}}. A row whose
    # body_text doesn't start with '{' (and isn't blank) is still plaintext.
    plain_mail = ActiveRecord::Base.connection.select_value(
      "SELECT COUNT(*) FROM mail_messages WHERE body_text IS NOT NULL AND body_text <> '' AND left(body_text, 1) <> '{'"
    )
    puts "mail_messages with plaintext-looking body_text: #{plain_mail}"
    puts "(all should be 0 after phi:encrypt)"
  end
end
