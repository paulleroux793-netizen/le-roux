# Phase 4 (P4.1/4.2/4.3) — Digital patient file, WhatsApp forms, digital notepad.
# ADDITIVE ONLY. Replaces the 5 physical files. Binary storage backend (Active Storage / disk)
# is wired later (UNCERTAINTIES #18); these tables hold the metadata + folder structure + form data.
class CreateDigitalFile < ActiveRecord::Migration[8.1]
  def change
    # A document in a patient's digital file. `folder` mirrors the practice's real folders.
    create_table :documents do |t|
      t.bigint  :patient_id, null: false
      t.bigint  :course_of_treatment_id
      t.string  :folder, null: false, default: "other"  # consent_forms / referral_letters / befores_afters / sidexis_scans / treatment_plans / correspondence / personal / aligners / other
      t.string  :title, null: false
      t.string  :doc_type, null: false, default: "file" # file / image / pdf / form / note / xray
      t.string  :source, null: false, default: "upload" # upload / whatsapp_form / notepad / sidexis / generated
      t.string  :file_name
      t.string  :content_type
      t.integer :byte_size
      t.string  :storage_key                              # path/key in the binary store (backend parked)
      t.boolean :signed, null: false, default: false
      t.datetime :captured_at, null: false
      t.string  :uploaded_by
      t.text     :notes
      t.timestamps
      t.index [ :patient_id, :folder ]
      t.index :course_of_treatment_id
      t.index :source
    end

    # Versioned form templates (medical history, consent, etc.) sent to patients.
    create_table :form_templates do |t|
      t.string  :key, null: false                # e.g. "medical_history", "consent_treatment"
      t.string  :name, null: false
      t.integer :version, null: false, default: 1
      t.jsonb   :schema, null: false, default: {} # field definitions
      t.boolean :requires_signature, null: false, default: true
      t.boolean :active, null: false, default: true
      t.timestamps
      t.index [ :key, :version ], unique: true
    end

    # A form sent to a patient and (optionally) completed on their phone via a tokenised link.
    create_table :form_submissions do |t|
      t.bigint  :form_template_id, null: false
      t.bigint  :patient_id, null: false
      t.string  :token, null: false              # tokenised, expiring mobile link
      t.string  :status, null: false, default: "sent"  # sent / opened / completed / expired
      t.jsonb   :data, null: false, default: {}   # the patient's answers
      t.text    :signature_data                   # captured e-signature (base64) — ECTA-valid
      t.datetime :sent_at
      t.datetime :opened_at
      t.datetime :completed_at
      t.datetime :expires_at
      t.bigint  :document_id                      # the filed PDF once completed
      t.timestamps
      t.index :token, unique: true
      t.index :patient_id
      t.index :status
    end

    # Digital notepad pages — write/annotate on a "page" instead of paper; saved to the file.
    create_table :notepad_pages do |t|
      t.bigint  :patient_id, null: false
      t.bigint  :course_of_treatment_id
      t.string  :title, null: false, default: "Note"
      t.text    :content                          # typed text and/or annotation payload
      t.string  :created_by
      t.bigint  :document_id                      # snapshot filed to the patient file
      t.timestamps
      t.index :patient_id
    end

    add_foreign_key :documents, :patients
    add_foreign_key :documents, :courses_of_treatment, column: :course_of_treatment_id
    add_foreign_key :form_submissions, :form_templates
    add_foreign_key :form_submissions, :patients
    add_foreign_key :form_submissions, :documents
    add_foreign_key :notepad_pages, :patients
    add_foreign_key :notepad_pages, :courses_of_treatment, column: :course_of_treatment_id
    add_foreign_key :notepad_pages, :documents
  end
end
