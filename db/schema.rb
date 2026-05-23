# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_05_23_000014) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "btree_gist"
  enable_extension "pg_catalog.plpgsql"

  create_table "account_patients", force: :cascade do |t|
    t.bigint "billing_account_id", null: false
    t.datetime "created_at", null: false
    t.bigint "patient_id", null: false
    t.string "relationship", default: "self", null: false
    t.datetime "updated_at", null: false
    t.index ["billing_account_id", "patient_id"], name: "idx_account_patients_unique", unique: true
    t.index ["patient_id"], name: "index_account_patients_on_patient_id"
  end

  create_table "analytics_events", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "event_type", null: false
    t.datetime "occurred_at", null: false
    t.jsonb "payload", default: {}, null: false
    t.string "request_id"
    t.string "session_id"
    t.datetime "updated_at", null: false
    t.index ["event_type", "occurred_at"], name: "index_analytics_events_on_event_type_and_occurred_at"
    t.index ["occurred_at"], name: "index_analytics_events_on_occurred_at"
  end

  create_table "appointments", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "end_time", null: false
    t.string "google_event_id"
    t.text "notes"
    t.bigint "patient_id", null: false
    t.string "reason"
    t.datetime "start_time", null: false
    t.integer "status", default: 0, null: false
    t.text "summary_decisions_text"
    t.text "summary_estimate_intent_text"
    t.datetime "summary_generated_at"
    t.jsonb "summary_patient_questions", default: [], null: false
    t.bigint "summary_scribe_session_id"
    t.datetime "updated_at", null: false
    t.index ["google_event_id"], name: "index_appointments_on_google_event_id", unique: true
    t.index ["patient_id"], name: "index_appointments_on_patient_id"
    t.index ["start_time"], name: "index_appointments_on_start_time"
    t.index ["status"], name: "index_appointments_on_status"
    t.index ["summary_generated_at"], name: "index_appointments_on_summary_generated_at"
    t.index ["summary_scribe_session_id"], name: "index_appointments_on_summary_scribe_session_id"
    t.exclusion_constraint "tsrange(start_time, end_time) WITH &&", where: "status <> 3", using: :gist, name: "no_overlapping_active_appointments"
  end

  create_table "audit_logs", force: :cascade do |t|
    t.string "action", null: false
    t.datetime "created_at", null: false
    t.jsonb "details", default: {}
    t.string "ip_address"
    t.string "performed_by"
    t.bigint "resource_id"
    t.string "resource_type"
    t.string "summary", null: false
    t.datetime "updated_at", null: false
    t.index ["action"], name: "index_audit_logs_on_action"
    t.index ["created_at"], name: "index_audit_logs_on_created_at"
    t.index ["performed_by"], name: "index_audit_logs_on_performed_by"
    t.index ["resource_type", "resource_id"], name: "index_audit_logs_on_resource_type_and_resource_id"
  end

  create_table "billing_accounts", force: :cascade do |t|
    t.string "account_code"
    t.string "address_line1"
    t.string "address_line2"
    t.string "billing_name", null: false
    t.string "city"
    t.datetime "created_at", null: false
    t.string "email"
    t.bigint "head_patient_id"
    t.text "notes"
    t.string "phone"
    t.string "postal_code"
    t.datetime "updated_at", null: false
    t.index ["account_code"], name: "index_billing_accounts_on_account_code", unique: true, where: "(account_code IS NOT NULL)"
    t.index ["billing_name"], name: "index_billing_accounts_on_billing_name"
    t.index ["head_patient_id"], name: "index_billing_accounts_on_head_patient_id"
  end

  create_table "calendar_notes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "done", default: false, null: false
    t.datetime "ends_at", null: false
    t.string "note", null: false
    t.datetime "starts_at", null: false
    t.datetime "updated_at", null: false
    t.index ["starts_at"], name: "index_calendar_notes_on_starts_at"
  end

  create_table "call_logs", force: :cascade do |t|
    t.text "ai_response"
    t.string "caller_number"
    t.datetime "created_at", null: false
    t.integer "duration"
    t.string "intent"
    t.bigint "patient_id"
    t.string "status"
    t.text "transcript"
    t.string "twilio_call_sid"
    t.datetime "updated_at", null: false
    t.index ["caller_number"], name: "index_call_logs_on_caller_number"
    t.index ["patient_id"], name: "index_call_logs_on_patient_id"
    t.index ["twilio_call_sid"], name: "index_call_logs_on_twilio_call_sid", unique: true
  end

  create_table "cancellation_reasons", force: :cascade do |t|
    t.bigint "appointment_id", null: false
    t.datetime "created_at", null: false
    t.text "details"
    t.string "reason_category", null: false
    t.datetime "updated_at", null: false
    t.index ["appointment_id"], name: "index_cancellation_reasons_on_appointment_id"
    t.index ["reason_category"], name: "index_cancellation_reasons_on_reason_category"
  end

  create_table "clinical_notes", force: :cascade do |t|
    t.text "assessment"
    t.bigint "course_of_treatment_id"
    t.datetime "created_at", null: false
    t.boolean "locked", default: false, null: false
    t.text "objective"
    t.bigint "patient_id", null: false
    t.text "plan"
    t.datetime "signed_at"
    t.string "signed_by"
    t.text "subjective"
    t.bigint "supersedes_id"
    t.datetime "updated_at", null: false
    t.index ["course_of_treatment_id"], name: "index_clinical_notes_on_course_of_treatment_id"
    t.index ["locked"], name: "index_clinical_notes_on_locked"
    t.index ["patient_id"], name: "index_clinical_notes_on_patient_id"
  end

  create_table "confirmation_logs", force: :cascade do |t|
    t.bigint "appointment_id", null: false
    t.integer "attempts", default: 0, null: false
    t.datetime "created_at", null: false
    t.boolean "flagged", default: false, null: false
    t.string "method", null: false
    t.text "notes"
    t.string "outcome"
    t.datetime "updated_at", null: false
    t.index ["appointment_id"], name: "index_confirmation_logs_on_appointment_id"
    t.index ["flagged"], name: "index_confirmation_logs_on_flagged"
    t.index ["outcome"], name: "index_confirmation_logs_on_outcome"
  end

  create_table "conversations", force: :cascade do |t|
    t.datetime "ai_paused_until"
    t.string "channel", null: false
    t.datetime "created_at", null: false
    t.datetime "ended_at"
    t.string "external_id"
    t.integer "follow_up_count", default: 0, null: false
    t.datetime "follow_up_sent_at"
    t.datetime "imported_at"
    t.string "language", limit: 5
    t.jsonb "messages", default: []
    t.bigint "patient_id", null: false
    t.string "source", default: "live", null: false
    t.datetime "started_at"
    t.string "status", default: "active", null: false
    t.jsonb "tags", default: [], null: false
    t.string "topic"
    t.datetime "updated_at", null: false
    t.index ["ai_paused_until"], name: "index_conversations_on_ai_paused_until", where: "(ai_paused_until IS NOT NULL)"
    t.index ["channel"], name: "index_conversations_on_channel"
    t.index ["external_id"], name: "index_conversations_on_external_id", unique: true
    t.index ["follow_up_sent_at"], name: "index_conversations_on_follow_up_sent_at"
    t.index ["patient_id"], name: "index_conversations_on_patient_id"
    t.index ["source"], name: "index_conversations_on_source"
    t.index ["status"], name: "index_conversations_on_status"
  end

  create_table "courses_of_treatment", force: :cascade do |t|
    t.string "authorisation_number"
    t.bigint "billing_account_id"
    t.datetime "created_at", null: false
    t.string "description"
    t.date "end_date"
    t.text "notes"
    t.bigint "patient_id", null: false
    t.bigint "scheme_membership_id"
    t.string "setting", default: "in_chair", null: false
    t.date "start_date"
    t.string "status", default: "planned", null: false
    t.datetime "updated_at", null: false
    t.index ["billing_account_id"], name: "index_courses_of_treatment_on_billing_account_id"
    t.index ["patient_id"], name: "index_courses_of_treatment_on_patient_id"
    t.index ["setting"], name: "index_courses_of_treatment_on_setting"
    t.index ["status"], name: "index_courses_of_treatment_on_status"
  end

  create_table "doctor_schedules", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.time "break_end"
    t.time "break_start"
    t.datetime "created_at", null: false
    t.integer "day_of_week"
    t.time "end_time"
    t.time "start_time"
    t.datetime "updated_at", null: false
    t.index ["day_of_week"], name: "index_doctor_schedules_on_day_of_week", unique: true
  end

  create_table "document_sequences", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "current_value", default: 0, null: false
    t.string "key", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_document_sequences_on_key", unique: true
  end

  create_table "documents", force: :cascade do |t|
    t.integer "byte_size"
    t.datetime "captured_at", null: false
    t.string "content_type"
    t.bigint "course_of_treatment_id"
    t.datetime "created_at", null: false
    t.string "doc_type", default: "file", null: false
    t.string "file_name"
    t.string "folder", default: "other", null: false
    t.text "notes"
    t.bigint "patient_id", null: false
    t.boolean "signed", default: false, null: false
    t.string "source", default: "upload", null: false
    t.string "storage_key"
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.string "uploaded_by"
    t.index ["course_of_treatment_id"], name: "index_documents_on_course_of_treatment_id"
    t.index ["patient_id", "folder"], name: "index_documents_on_patient_id_and_folder"
    t.index ["source"], name: "index_documents_on_source"
  end

  create_table "estimate_lines", force: :cascade do |t|
    t.string "code"
    t.datetime "created_at", null: false
    t.string "description"
    t.bigint "estimate_id", null: false
    t.string "icd10_code"
    t.integer "line_total_cents", default: 0, null: false
    t.integer "medical_cents", default: 0, null: false
    t.bigint "procedure_code_id"
    t.integer "quantity", default: 1, null: false
    t.integer "self_cents", default: 0, null: false
    t.string "tooth_number"
    t.bigint "treatment_item_id"
    t.integer "unit_fee_cents", default: 0, null: false
    t.datetime "updated_at", null: false
    t.integer "vat_cents", default: 0, null: false
    t.string "vat_treatment", default: "zero_rated", null: false
    t.integer "visit", default: 1, null: false
    t.index ["estimate_id"], name: "index_estimate_lines_on_estimate_id"
  end

  create_table "estimates", force: :cascade do |t|
    t.datetime "accepted_at"
    t.bigint "billing_account_id"
    t.bigint "course_of_treatment_id"
    t.datetime "created_at", null: false
    t.string "estimate_number", null: false
    t.text "notes"
    t.bigint "patient_id", null: false
    t.datetime "sent_at"
    t.string "status", default: "draft", null: false
    t.integer "subtotal_cents", default: 0, null: false
    t.integer "total_cents", default: 0, null: false
    t.datetime "updated_at", null: false
    t.date "valid_until"
    t.integer "vat_cents", default: 0, null: false
    t.index ["course_of_treatment_id"], name: "index_estimates_on_course_of_treatment_id"
    t.index ["estimate_number"], name: "index_estimates_on_estimate_number", unique: true
    t.index ["patient_id"], name: "index_estimates_on_patient_id"
    t.index ["status"], name: "index_estimates_on_status"
  end

  create_table "fee_schedule_items", force: :cascade do |t|
    t.integer "allowed_amount_cents"
    t.datetime "created_at", null: false
    t.bigint "fee_schedule_id", null: false
    t.integer "practice_fee_cents", default: 0, null: false
    t.bigint "procedure_code_id", null: false
    t.datetime "updated_at", null: false
    t.index ["fee_schedule_id", "procedure_code_id"], name: "idx_fee_schedule_items_unique", unique: true
    t.index ["procedure_code_id"], name: "index_fee_schedule_items_on_procedure_code_id"
  end

  create_table "fee_schedules", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.bigint "medical_scheme_id"
    t.string "name", null: false
    t.string "plan_option"
    t.datetime "updated_at", null: false
    t.integer "year"
    t.index ["medical_scheme_id"], name: "index_fee_schedules_on_medical_scheme_id"
    t.index ["name", "year"], name: "index_fee_schedules_on_name_and_year"
  end

  create_table "form_submissions", force: :cascade do |t|
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.jsonb "data", default: {}, null: false
    t.bigint "document_id"
    t.datetime "expires_at"
    t.bigint "form_template_id", null: false
    t.datetime "opened_at"
    t.bigint "patient_id", null: false
    t.datetime "sent_at"
    t.text "signature_data"
    t.string "status", default: "sent", null: false
    t.string "token", null: false
    t.datetime "updated_at", null: false
    t.index ["patient_id"], name: "index_form_submissions_on_patient_id"
    t.index ["status"], name: "index_form_submissions_on_status"
    t.index ["token"], name: "index_form_submissions_on_token", unique: true
  end

  create_table "form_templates", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.string "key", null: false
    t.string "name", null: false
    t.boolean "requires_signature", default: true, null: false
    t.jsonb "schema", default: {}, null: false
    t.datetime "updated_at", null: false
    t.integer "version", default: 1, null: false
    t.index ["key", "version"], name: "index_form_templates_on_key_and_version", unique: true
  end

  create_table "icd10_codes", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.string "category"
    t.string "code", null: false
    t.datetime "created_at", null: false
    t.string "description", null: false
    t.datetime "updated_at", null: false
    t.index ["category"], name: "index_icd10_codes_on_category"
    t.index ["code"], name: "index_icd10_codes_on_code", unique: true
  end

  create_table "imaging_studies", force: :cascade do |t|
    t.datetime "captured_at"
    t.datetime "created_at", null: false
    t.string "modality", default: "other", null: false
    t.text "notes"
    t.bigint "patient_id"
    t.string "sidexis_patient_name"
    t.string "source_file"
    t.string "source_folder"
    t.string "status", default: "needs_match", null: false
    t.string "storage_key"
    t.datetime "updated_at", null: false
    t.index ["modality"], name: "index_imaging_studies_on_modality"
    t.index ["patient_id"], name: "index_imaging_studies_on_patient_id"
    t.index ["source_folder", "source_file"], name: "idx_imaging_unique_source", unique: true
    t.index ["status"], name: "index_imaging_studies_on_status"
  end

  create_table "invoice_lines", force: :cascade do |t|
    t.string "code"
    t.datetime "created_at", null: false
    t.string "description"
    t.string "icd10_code"
    t.bigint "invoice_id", null: false
    t.integer "line_total_cents", default: 0, null: false
    t.integer "medical_cents", default: 0, null: false
    t.bigint "procedure_code_id"
    t.integer "quantity", default: 1, null: false
    t.integer "self_cents", default: 0, null: false
    t.string "tooth_number"
    t.bigint "treatment_item_id"
    t.integer "unit_fee_cents", default: 0, null: false
    t.datetime "updated_at", null: false
    t.integer "vat_cents", default: 0, null: false
    t.string "vat_treatment", default: "zero_rated", null: false
    t.index ["invoice_id"], name: "index_invoice_lines_on_invoice_id"
  end

  create_table "invoices", force: :cascade do |t|
    t.bigint "billing_account_id"
    t.bigint "course_of_treatment_id"
    t.datetime "created_at", null: false
    t.date "invoice_date", null: false
    t.string "invoice_number", null: false
    t.text "notes"
    t.integer "paid_cents", default: 0, null: false
    t.bigint "patient_id", null: false
    t.string "status", default: "open", null: false
    t.integer "subtotal_cents", default: 0, null: false
    t.integer "total_cents", default: 0, null: false
    t.datetime "updated_at", null: false
    t.integer "vat_cents", default: 0, null: false
    t.boolean "void", default: false, null: false
    t.index ["billing_account_id"], name: "index_invoices_on_billing_account_id"
    t.index ["invoice_number"], name: "index_invoices_on_invoice_number", unique: true
    t.index ["patient_id"], name: "index_invoices_on_patient_id"
    t.index ["status"], name: "index_invoices_on_status"
  end

  create_table "medical_schemes", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.string "administrator"
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.string "scheme_code"
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_medical_schemes_on_name"
    t.index ["scheme_code"], name: "index_medical_schemes_on_scheme_code", unique: true, where: "(scheme_code IS NOT NULL)"
  end

  create_table "notepad_pages", force: :cascade do |t|
    t.text "content"
    t.bigint "course_of_treatment_id"
    t.datetime "created_at", null: false
    t.string "created_by"
    t.bigint "document_id"
    t.bigint "patient_id", null: false
    t.string "title", default: "Note", null: false
    t.datetime "updated_at", null: false
    t.index ["patient_id"], name: "index_notepad_pages_on_patient_id"
  end

  create_table "notifications", force: :cascade do |t|
    t.bigint "appointment_id"
    t.text "body"
    t.string "category", null: false
    t.bigint "conversation_id"
    t.datetime "created_at", null: false
    t.string "level", default: "info", null: false
    t.bigint "patient_id"
    t.datetime "read_at"
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.string "url"
    t.index ["appointment_id"], name: "index_notifications_on_appointment_id"
    t.index ["category"], name: "index_notifications_on_category"
    t.index ["conversation_id"], name: "index_notifications_on_conversation_id"
    t.index ["created_at"], name: "index_notifications_on_created_at"
    t.index ["patient_id"], name: "index_notifications_on_patient_id"
    t.index ["read_at"], name: "index_notifications_on_unread", where: "(read_at IS NULL)"
  end

  create_table "patient_medical_histories", force: :cascade do |t|
    t.text "allergies"
    t.string "blood_type"
    t.text "chronic_conditions"
    t.datetime "created_at", null: false
    t.text "current_medications"
    t.text "dental_notes"
    t.string "emergency_contact_name"
    t.string "emergency_contact_phone"
    t.string "insurance_policy_number"
    t.string "insurance_provider"
    t.date "last_dental_visit"
    t.bigint "patient_id", null: false
    t.datetime "updated_at", null: false
    t.index ["patient_id"], name: "index_patient_medical_histories_on_patient_id", unique: true
  end

  create_table "patients", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.date "date_of_birth"
    t.string "email"
    t.string "first_name", null: false
    t.string "id_number"
    t.string "last_name", null: false
    t.text "notes"
    t.string "phone"
    t.string "preferred_language", limit: 5
    t.datetime "updated_at", null: false
    t.index ["id_number"], name: "index_patients_on_id_number", where: "(id_number IS NOT NULL)"
    t.index ["last_name", "first_name"], name: "index_patients_on_last_name_and_first_name"
    t.index ["phone"], name: "index_patients_on_phone", unique: true
    t.index ["preferred_language"], name: "index_patients_on_preferred_language"
  end

  create_table "payments", force: :cascade do |t|
    t.integer "amount_cents", null: false
    t.bigint "billing_account_id"
    t.datetime "created_at", null: false
    t.bigint "invoice_id"
    t.boolean "is_deposit", default: false, null: false
    t.string "method", default: "card", null: false
    t.text "notes"
    t.bigint "patient_id"
    t.datetime "received_at", null: false
    t.string "reference"
    t.datetime "updated_at", null: false
    t.index ["billing_account_id"], name: "index_payments_on_billing_account_id"
    t.index ["invoice_id"], name: "index_payments_on_invoice_id"
    t.index ["received_at"], name: "index_payments_on_received_at"
  end

  create_table "practice_billing_profiles", force: :cascade do |t|
    t.string "address_line1"
    t.string "address_line2"
    t.string "bank_account_name"
    t.string "bank_account_number"
    t.string "bank_branch_code"
    t.string "bank_name"
    t.string "bhf_practice_number"
    t.string "city"
    t.string "company_reg"
    t.datetime "created_at", null: false
    t.string "email"
    t.string "hpcsa_number"
    t.string "phone"
    t.string "postal_code"
    t.string "practice_name", default: "Dr Chalita le Roux Inc", null: false
    t.string "practitioner_bhf_number"
    t.string "practitioner_hpcsa_number"
    t.string "practitioner_name"
    t.datetime "updated_at", null: false
    t.string "vat_number"
    t.boolean "vat_registered", default: false, null: false
  end

  create_table "practice_settings", force: :cascade do |t|
    t.string "address_line1"
    t.string "address_line2"
    t.text "admin_instructions"
    t.jsonb "admin_modes", default: {}
    t.string "city"
    t.datetime "created_at", null: false
    t.string "email"
    t.string "emergency_phone"
    t.string "map_link"
    t.string "name", default: "Dr Chalita le Roux Inc", null: false
    t.string "phone"
    t.string "price_check_up"
    t.string "price_cleaning"
    t.string "price_consultation"
    t.datetime "updated_at", null: false
  end

  create_table "procedure_codes", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.integer "age_max"
    t.integer "age_min"
    t.string "category"
    t.string "code", null: false
    t.datetime "created_at", null: false
    t.integer "default_fee_cents"
    t.string "description", null: false
    t.boolean "lab_fee_applicable", default: false, null: false
    t.boolean "material_fee_applicable", default: false, null: false
    t.integer "max_per_year"
    t.integer "medical_fee_cents"
    t.boolean "requires_authorisation", default: false, null: false
    t.boolean "tooth_specific", default: false, null: false
    t.datetime "updated_at", null: false
    t.string "vat_treatment", default: "zero_rated", null: false
    t.index ["active"], name: "index_procedure_codes_on_active"
    t.index ["category"], name: "index_procedure_codes_on_category"
    t.index ["code"], name: "index_procedure_codes_on_code", unique: true
  end

  create_table "recalls", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.date "due_on", null: false
    t.datetime "last_contacted_at"
    t.text "notes"
    t.bigint "patient_id", null: false
    t.string "recall_type", default: "checkup", null: false
    t.string "status", default: "due", null: false
    t.datetime "updated_at", null: false
    t.index ["patient_id", "due_on"], name: "index_recalls_on_patient_id_and_due_on"
    t.index ["status"], name: "index_recalls_on_status"
  end

  create_table "recording_devices", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "enabled", default: true, null: false
    t.datetime "last_seen_at"
    t.string "location", null: false
    t.string "name", null: false
    t.text "notes"
    t.datetime "updated_at", null: false
    t.index ["location"], name: "index_recording_devices_on_location"
    t.index ["name"], name: "index_recording_devices_on_name", unique: true
  end

  create_table "scheme_membership_patients", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "dependant_code"
    t.bigint "patient_id", null: false
    t.string "role", default: "dependant", null: false
    t.bigint "scheme_membership_id", null: false
    t.datetime "updated_at", null: false
    t.index ["patient_id"], name: "index_scheme_membership_patients_on_patient_id"
    t.index ["scheme_membership_id", "patient_id"], name: "idx_scheme_membership_patients_unique", unique: true
  end

  create_table "scheme_memberships", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.date "effective_from"
    t.date "effective_to"
    t.string "main_member_name"
    t.bigint "main_member_patient_id"
    t.bigint "medical_scheme_id", null: false
    t.string "member_number", null: false
    t.string "plan_option"
    t.datetime "updated_at", null: false
    t.index ["main_member_patient_id"], name: "index_scheme_memberships_on_main_member_patient_id"
    t.index ["medical_scheme_id"], name: "index_scheme_memberships_on_medical_scheme_id"
    t.index ["member_number"], name: "index_scheme_memberships_on_member_number"
  end

  create_table "scribe_sessions", force: :cascade do |t|
    t.bigint "appointment_id"
    t.bigint "course_of_treatment_id"
    t.datetime "created_at", null: false
    t.jsonb "draft", default: {}, null: false
    t.datetime "ended_at"
    t.bigint "estimate_id"
    t.text "notes"
    t.bigint "patient_id", null: false
    t.bigint "recording_device_id"
    t.datetime "started_at"
    t.string "status", default: "recording", null: false
    t.text "transcript"
    t.datetime "updated_at", null: false
    t.index ["appointment_id"], name: "index_scribe_sessions_on_appointment_id"
    t.index ["patient_id"], name: "index_scribe_sessions_on_patient_id"
    t.index ["recording_device_id"], name: "index_scribe_sessions_on_recording_device_id"
    t.index ["status"], name: "index_scribe_sessions_on_status"
  end

  create_table "solid_cable_messages", force: :cascade do |t|
    t.binary "channel", null: false
    t.bigint "channel_hash", null: false
    t.datetime "created_at", null: false
    t.binary "payload", null: false
    t.index ["channel"], name: "index_solid_cable_messages_on_channel"
    t.index ["channel_hash"], name: "index_solid_cable_messages_on_channel_hash"
    t.index ["created_at"], name: "index_solid_cable_messages_on_created_at"
  end

  create_table "solid_cache_entries", force: :cascade do |t|
    t.integer "byte_size", null: false
    t.datetime "created_at", null: false
    t.binary "key", null: false
    t.bigint "key_hash", null: false
    t.binary "value", null: false
    t.index ["byte_size"], name: "index_solid_cache_entries_on_byte_size"
    t.index ["key_hash", "byte_size"], name: "index_solid_cache_entries_on_key_hash_and_byte_size"
    t.index ["key_hash"], name: "index_solid_cache_entries_on_key_hash", unique: true
  end

  create_table "solid_queue_blocked_executions", force: :cascade do |t|
    t.string "concurrency_key", null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.index ["concurrency_key", "priority", "job_id"], name: "index_solid_queue_blocked_executions_for_release"
    t.index ["expires_at", "concurrency_key"], name: "index_solid_queue_blocked_executions_for_maintenance"
    t.index ["job_id"], name: "index_solid_queue_blocked_executions_on_job_id", unique: true
  end

  create_table "solid_queue_claimed_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.bigint "process_id"
    t.index ["job_id"], name: "index_solid_queue_claimed_executions_on_job_id", unique: true
    t.index ["process_id", "job_id"], name: "index_solid_queue_claimed_executions_on_process_id_and_job_id"
  end

  create_table "solid_queue_failed_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "error"
    t.bigint "job_id", null: false
    t.index ["job_id"], name: "index_solid_queue_failed_executions_on_job_id", unique: true
  end

  create_table "solid_queue_jobs", force: :cascade do |t|
    t.string "active_job_id"
    t.text "arguments"
    t.string "class_name", null: false
    t.string "concurrency_key"
    t.datetime "created_at", null: false
    t.datetime "finished_at"
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.datetime "scheduled_at"
    t.datetime "updated_at", null: false
    t.index ["active_job_id"], name: "index_solid_queue_jobs_on_active_job_id"
    t.index ["class_name"], name: "index_solid_queue_jobs_on_class_name"
    t.index ["finished_at"], name: "index_solid_queue_jobs_on_finished_at"
    t.index ["queue_name", "finished_at"], name: "index_solid_queue_jobs_for_filtering"
    t.index ["scheduled_at", "finished_at"], name: "index_solid_queue_jobs_for_alerting"
  end

  create_table "solid_queue_pauses", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "queue_name", null: false
    t.index ["queue_name"], name: "index_solid_queue_pauses_on_queue_name", unique: true
  end

  create_table "solid_queue_processes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "hostname"
    t.string "kind", null: false
    t.datetime "last_heartbeat_at", null: false
    t.text "metadata"
    t.string "name", null: false
    t.integer "pid", null: false
    t.bigint "supervisor_id"
    t.index ["last_heartbeat_at"], name: "index_solid_queue_processes_on_last_heartbeat_at"
    t.index ["name", "supervisor_id"], name: "index_solid_queue_processes_on_name_and_supervisor_id", unique: true
    t.index ["supervisor_id"], name: "index_solid_queue_processes_on_supervisor_id"
  end

  create_table "solid_queue_ready_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.index ["job_id"], name: "index_solid_queue_ready_executions_on_job_id", unique: true
    t.index ["priority", "job_id"], name: "index_solid_queue_poll_all"
    t.index ["queue_name", "priority", "job_id"], name: "index_solid_queue_poll_by_queue"
  end

  create_table "solid_queue_recurring_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.datetime "run_at", null: false
    t.string "task_key", null: false
    t.index ["job_id"], name: "index_solid_queue_recurring_executions_on_job_id", unique: true
    t.index ["task_key", "run_at"], name: "index_solid_queue_recurring_executions_on_task_key_and_run_at", unique: true
  end

  create_table "solid_queue_recurring_tasks", force: :cascade do |t|
    t.text "arguments"
    t.string "class_name"
    t.string "command", limit: 2048
    t.datetime "created_at", null: false
    t.text "description"
    t.string "key", null: false
    t.integer "priority", default: 0
    t.string "queue_name"
    t.string "schedule", null: false
    t.boolean "static", default: true, null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_solid_queue_recurring_tasks_on_key", unique: true
    t.index ["static"], name: "index_solid_queue_recurring_tasks_on_static"
  end

  create_table "solid_queue_scheduled_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.datetime "scheduled_at", null: false
    t.index ["job_id"], name: "index_solid_queue_scheduled_executions_on_job_id", unique: true
    t.index ["scheduled_at", "priority", "job_id"], name: "index_solid_queue_dispatch_all"
  end

  create_table "solid_queue_semaphores", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.string "key", null: false
    t.datetime "updated_at", null: false
    t.integer "value", default: 1, null: false
    t.index ["expires_at"], name: "index_solid_queue_semaphores_on_expires_at"
    t.index ["key", "value"], name: "index_solid_queue_semaphores_on_key_and_value"
    t.index ["key"], name: "index_solid_queue_semaphores_on_key", unique: true
  end

  create_table "statements", force: :cascade do |t|
    t.bigint "billing_account_id", null: false
    t.integer "closing_balance_cents", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "generated_at", null: false
    t.integer "opening_balance_cents", default: 0, null: false
    t.date "period_end"
    t.date "period_start"
    t.string "statement_number", null: false
    t.datetime "updated_at", null: false
    t.index ["billing_account_id"], name: "index_statements_on_billing_account_id"
    t.index ["statement_number"], name: "index_statements_on_statement_number", unique: true
  end

  create_table "tooth_chart_entries", force: :cascade do |t|
    t.string "condition", null: false
    t.bigint "course_of_treatment_id"
    t.datetime "created_at", null: false
    t.datetime "noted_at", null: false
    t.string "noted_by"
    t.bigint "patient_id", null: false
    t.string "surface"
    t.string "tooth_number", null: false
    t.bigint "treatment_item_id"
    t.datetime "updated_at", null: false
    t.index ["course_of_treatment_id"], name: "index_tooth_chart_entries_on_course_of_treatment_id"
    t.index ["patient_id", "tooth_number"], name: "index_tooth_chart_entries_on_patient_id_and_tooth_number"
  end

  create_table "treatment_items", force: :cascade do |t|
    t.date "completed_date"
    t.bigint "course_of_treatment_id", null: false
    t.datetime "created_at", null: false
    t.integer "fee_cents"
    t.string "icd10_code"
    t.text "notes"
    t.date "planned_date"
    t.bigint "procedure_code_id", null: false
    t.string "provider_name"
    t.string "status", default: "planned", null: false
    t.string "surface"
    t.string "tooth_number"
    t.datetime "updated_at", null: false
    t.string "vat_treatment", default: "zero_rated", null: false
    t.integer "visit", default: 1, null: false
    t.index ["course_of_treatment_id"], name: "index_treatment_items_on_course_of_treatment_id"
    t.index ["procedure_code_id"], name: "index_treatment_items_on_procedure_code_id"
    t.index ["status"], name: "index_treatment_items_on_status"
  end

  create_table "treatment_macro_items", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "more_info"
    t.integer "position", default: 0, null: false
    t.bigint "procedure_code_id"
    t.integer "quantity", default: 1, null: false
    t.string "tariff_code"
    t.bigint "treatment_macro_id", null: false
    t.datetime "updated_at", null: false
    t.index ["procedure_code_id"], name: "index_treatment_macro_items_on_procedure_code_id"
    t.index ["treatment_macro_id"], name: "index_treatment_macro_items_on_treatment_macro_id"
  end

  create_table "treatment_macros", force: :cascade do |t|
    t.string "access_code", null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.boolean "laboratory", default: false, null: false
    t.string "name", null: false
    t.text "notes"
    t.datetime "updated_at", null: false
    t.index ["access_code"], name: "index_treatment_macros_on_access_code", unique: true
  end

  add_foreign_key "account_patients", "billing_accounts"
  add_foreign_key "account_patients", "patients"
  add_foreign_key "appointments", "patients"
  add_foreign_key "appointments", "scribe_sessions", column: "summary_scribe_session_id"
  add_foreign_key "billing_accounts", "patients", column: "head_patient_id"
  add_foreign_key "call_logs", "patients"
  add_foreign_key "cancellation_reasons", "appointments"
  add_foreign_key "clinical_notes", "clinical_notes", column: "supersedes_id"
  add_foreign_key "clinical_notes", "courses_of_treatment", column: "course_of_treatment_id"
  add_foreign_key "clinical_notes", "patients"
  add_foreign_key "confirmation_logs", "appointments"
  add_foreign_key "conversations", "patients"
  add_foreign_key "courses_of_treatment", "billing_accounts"
  add_foreign_key "courses_of_treatment", "patients"
  add_foreign_key "courses_of_treatment", "scheme_memberships"
  add_foreign_key "documents", "courses_of_treatment", column: "course_of_treatment_id"
  add_foreign_key "documents", "patients"
  add_foreign_key "estimate_lines", "estimates"
  add_foreign_key "estimates", "billing_accounts"
  add_foreign_key "estimates", "courses_of_treatment", column: "course_of_treatment_id"
  add_foreign_key "estimates", "patients"
  add_foreign_key "fee_schedule_items", "fee_schedules"
  add_foreign_key "fee_schedule_items", "procedure_codes"
  add_foreign_key "fee_schedules", "medical_schemes"
  add_foreign_key "form_submissions", "documents", on_delete: :nullify
  add_foreign_key "form_submissions", "form_templates"
  add_foreign_key "form_submissions", "patients"
  add_foreign_key "imaging_studies", "patients"
  add_foreign_key "invoice_lines", "invoices"
  add_foreign_key "invoices", "billing_accounts"
  add_foreign_key "invoices", "courses_of_treatment", column: "course_of_treatment_id"
  add_foreign_key "invoices", "patients"
  add_foreign_key "notepad_pages", "courses_of_treatment", column: "course_of_treatment_id"
  add_foreign_key "notepad_pages", "documents", on_delete: :nullify
  add_foreign_key "notepad_pages", "patients"
  add_foreign_key "notifications", "appointments"
  add_foreign_key "notifications", "conversations"
  add_foreign_key "notifications", "patients"
  add_foreign_key "patient_medical_histories", "patients"
  add_foreign_key "payments", "billing_accounts"
  add_foreign_key "payments", "invoices"
  add_foreign_key "recalls", "patients"
  add_foreign_key "scheme_membership_patients", "patients"
  add_foreign_key "scheme_membership_patients", "scheme_memberships"
  add_foreign_key "scheme_memberships", "medical_schemes"
  add_foreign_key "scheme_memberships", "patients", column: "main_member_patient_id"
  add_foreign_key "scribe_sessions", "appointments"
  add_foreign_key "scribe_sessions", "courses_of_treatment", column: "course_of_treatment_id", on_delete: :nullify
  add_foreign_key "scribe_sessions", "estimates", on_delete: :nullify
  add_foreign_key "scribe_sessions", "patients"
  add_foreign_key "scribe_sessions", "recording_devices"
  add_foreign_key "solid_queue_blocked_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_claimed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_failed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_ready_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_recurring_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_scheduled_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "statements", "billing_accounts"
  add_foreign_key "tooth_chart_entries", "courses_of_treatment", column: "course_of_treatment_id"
  add_foreign_key "tooth_chart_entries", "patients"
  add_foreign_key "tooth_chart_entries", "treatment_items"
  add_foreign_key "treatment_items", "courses_of_treatment", column: "course_of_treatment_id"
  add_foreign_key "treatment_items", "procedure_codes"
  add_foreign_key "treatment_macro_items", "procedure_codes"
  add_foreign_key "treatment_macro_items", "treatment_macros"
end
