# Widen the columns that will hold encrypted PHI. Application-level encryption
# (Active Record `encrypts`) produces ciphertext LONGER than the plaintext, so
# `string` (varchar 255) columns are promoted to `text`, and form_submissions.data
# moves from jsonb to text (the ciphertext is an opaque string, not JSON).
#
# This migration only changes COLUMN TYPES. The existing rows stay plaintext until
# `bin/rails phi:encrypt` re-encrypts them in place (support_unencrypted_data keeps
# reads working in between). REHEARSE on a local Docker copy of prod first.
#
# Columns already typed `text` (allergies, chronic_conditions, current_medications,
# dental_notes) need no change here — only their models gain `encrypts`.
class EncryptPhiColumns < ActiveRecord::Migration[8.1]
  def up
    change_column :patients, :id_number, :text

    change_column :patient_medical_histories, :emergency_contact_name, :text
    change_column :patient_medical_histories, :emergency_contact_phone, :text
    change_column :patient_medical_histories, :insurance_policy_number, :text

    # jsonb -> text: Postgres casts jsonb to its canonical JSON string, so existing
    # answers survive as readable JSON until the backfill encrypts them.
    change_column_default :form_submissions, :data, nil
    change_column :form_submissions, :data, :text, using: "data::text"
  end

  def down
    change_column :patients, :id_number, :string

    change_column :patient_medical_histories, :emergency_contact_name, :string
    change_column :patient_medical_histories, :emergency_contact_phone, :string
    change_column :patient_medical_histories, :insurance_policy_number, :string

    # Only reversible if the data is still plaintext JSON (i.e. before phi:encrypt).
    change_column :form_submissions, :data, :jsonb, using: "data::jsonb"
    change_column_default :form_submissions, :data, {}
  end
end
