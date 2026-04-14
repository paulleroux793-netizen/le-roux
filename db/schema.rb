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

ActiveRecord::Schema[8.1].define(version: 2026_04_14_120000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "appointments", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "end_time", null: false
    t.string "google_event_id"
    t.text "notes"
    t.bigint "patient_id", null: false
    t.string "reason"
    t.datetime "start_time", null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["google_event_id"], name: "index_appointments_on_google_event_id", unique: true
    t.index ["patient_id"], name: "index_appointments_on_patient_id"
    t.index ["start_time"], name: "index_appointments_on_start_time"
    t.index ["status"], name: "index_appointments_on_status"
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
    t.string "channel", null: false
    t.datetime "created_at", null: false
    t.datetime "ended_at"
    t.string "external_id"
    t.datetime "imported_at"
    t.jsonb "messages", default: []
    t.bigint "patient_id", null: false
    t.string "source", default: "live", null: false
    t.datetime "started_at"
    t.string "status", default: "active", null: false
    t.string "topic"
    t.datetime "updated_at", null: false
    t.index ["channel"], name: "index_conversations_on_channel"
    t.index ["external_id"], name: "index_conversations_on_external_id", unique: true
    t.index ["patient_id"], name: "index_conversations_on_patient_id"
    t.index ["source"], name: "index_conversations_on_source"
    t.index ["status"], name: "index_conversations_on_status"
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
    t.string "last_name", null: false
    t.text "notes"
    t.string "phone", null: false
    t.datetime "updated_at", null: false
    t.index ["last_name", "first_name"], name: "index_patients_on_last_name_and_first_name"
    t.index ["phone"], name: "index_patients_on_phone", unique: true
  end

  add_foreign_key "appointments", "patients"
  add_foreign_key "call_logs", "patients"
  add_foreign_key "cancellation_reasons", "appointments"
  add_foreign_key "confirmation_logs", "appointments"
  add_foreign_key "conversations", "patients"
  add_foreign_key "notifications", "appointments"
  add_foreign_key "notifications", "conversations"
  add_foreign_key "notifications", "patients"
  add_foreign_key "patient_medical_histories", "patients"
end
