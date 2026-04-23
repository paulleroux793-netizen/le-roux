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

ActiveRecord::Schema[8.1].define(version: 2026_04_23_000001) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "public.analytics_events", force: :cascade do |t|
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

  create_table "public.appointments", force: :cascade do |t|
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

  create_table "public.audit_logs", force: :cascade do |t|
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

  create_table "public.call_logs", force: :cascade do |t|
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

  create_table "public.cancellation_reasons", force: :cascade do |t|
    t.bigint "appointment_id", null: false
    t.datetime "created_at", null: false
    t.text "details"
    t.string "reason_category", null: false
    t.datetime "updated_at", null: false
    t.index ["appointment_id"], name: "index_cancellation_reasons_on_appointment_id"
    t.index ["reason_category"], name: "index_cancellation_reasons_on_reason_category"
  end

  create_table "public.confirmation_logs", force: :cascade do |t|
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

  create_table "public.conversations", force: :cascade do |t|
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
    t.index ["channel"], name: "index_conversations_on_channel"
    t.index ["external_id"], name: "index_conversations_on_external_id", unique: true
    t.index ["follow_up_sent_at"], name: "index_conversations_on_follow_up_sent_at"
    t.index ["patient_id"], name: "index_conversations_on_patient_id"
    t.index ["source"], name: "index_conversations_on_source"
    t.index ["status"], name: "index_conversations_on_status"
  end

  create_table "public.doctor_schedules", force: :cascade do |t|
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

  create_table "public.notifications", force: :cascade do |t|
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

  create_table "public.patient_medical_histories", force: :cascade do |t|
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

  create_table "public.patients", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.date "date_of_birth"
    t.string "email"
    t.string "first_name", null: false
    t.string "last_name", null: false
    t.text "notes"
    t.string "phone", null: false
    t.string "preferred_language", limit: 5
    t.datetime "updated_at", null: false
    t.index ["last_name", "first_name"], name: "index_patients_on_last_name_and_first_name"
    t.index ["phone"], name: "index_patients_on_phone", unique: true
    t.index ["preferred_language"], name: "index_patients_on_preferred_language"
  end

  create_table "public.practice_settings", force: :cascade do |t|
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

  create_table "public.solid_cable_messages", force: :cascade do |t|
    t.binary "channel", null: false
    t.bigint "channel_hash", null: false
    t.datetime "created_at", null: false
    t.binary "payload", null: false
    t.index ["channel"], name: "index_solid_cable_messages_on_channel"
    t.index ["channel_hash"], name: "index_solid_cable_messages_on_channel_hash"
    t.index ["created_at"], name: "index_solid_cable_messages_on_created_at"
  end

  create_table "public.solid_cache_entries", force: :cascade do |t|
    t.integer "byte_size", null: false
    t.datetime "created_at", null: false
    t.binary "key", null: false
    t.bigint "key_hash", null: false
    t.binary "value", null: false
    t.index ["byte_size"], name: "index_solid_cache_entries_on_byte_size"
    t.index ["key_hash", "byte_size"], name: "index_solid_cache_entries_on_key_hash_and_byte_size"
    t.index ["key_hash"], name: "index_solid_cache_entries_on_key_hash", unique: true
  end

  create_table "public.solid_queue_blocked_executions", force: :cascade do |t|
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

  create_table "public.solid_queue_claimed_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.bigint "process_id"
    t.index ["job_id"], name: "index_solid_queue_claimed_executions_on_job_id", unique: true
    t.index ["process_id", "job_id"], name: "index_solid_queue_claimed_executions_on_process_id_and_job_id"
  end

  create_table "public.solid_queue_failed_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "error"
    t.bigint "job_id", null: false
    t.index ["job_id"], name: "index_solid_queue_failed_executions_on_job_id", unique: true
  end

  create_table "public.solid_queue_jobs", force: :cascade do |t|
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

  create_table "public.solid_queue_pauses", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "queue_name", null: false
    t.index ["queue_name"], name: "index_solid_queue_pauses_on_queue_name", unique: true
  end

  create_table "public.solid_queue_processes", force: :cascade do |t|
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

  create_table "public.solid_queue_ready_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.index ["job_id"], name: "index_solid_queue_ready_executions_on_job_id", unique: true
    t.index ["priority", "job_id"], name: "index_solid_queue_poll_all"
    t.index ["queue_name", "priority", "job_id"], name: "index_solid_queue_poll_by_queue"
  end

  create_table "public.solid_queue_recurring_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.datetime "run_at", null: false
    t.string "task_key", null: false
    t.index ["job_id"], name: "index_solid_queue_recurring_executions_on_job_id", unique: true
    t.index ["task_key", "run_at"], name: "index_solid_queue_recurring_executions_on_task_key_and_run_at", unique: true
  end

  create_table "public.solid_queue_recurring_tasks", force: :cascade do |t|
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

  create_table "public.solid_queue_scheduled_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.datetime "scheduled_at", null: false
    t.index ["job_id"], name: "index_solid_queue_scheduled_executions_on_job_id", unique: true
    t.index ["scheduled_at", "priority", "job_id"], name: "index_solid_queue_dispatch_all"
  end

  create_table "public.solid_queue_semaphores", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.string "key", null: false
    t.datetime "updated_at", null: false
    t.integer "value", default: 1, null: false
    t.index ["expires_at"], name: "index_solid_queue_semaphores_on_expires_at"
    t.index ["key", "value"], name: "index_solid_queue_semaphores_on_key_and_value"
    t.index ["key"], name: "index_solid_queue_semaphores_on_key", unique: true
  end

  add_foreign_key "public.appointments", "public.patients"
  add_foreign_key "public.call_logs", "public.patients"
  add_foreign_key "public.cancellation_reasons", "public.appointments"
  add_foreign_key "public.confirmation_logs", "public.appointments"
  add_foreign_key "public.conversations", "public.patients"
  add_foreign_key "public.notifications", "public.appointments"
  add_foreign_key "public.notifications", "public.conversations"
  add_foreign_key "public.notifications", "public.patients"
  add_foreign_key "public.patient_medical_histories", "public.patients"
  add_foreign_key "public.solid_queue_blocked_executions", "public.solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "public.solid_queue_claimed_executions", "public.solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "public.solid_queue_failed_executions", "public.solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "public.solid_queue_ready_executions", "public.solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "public.solid_queue_recurring_executions", "public.solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "public.solid_queue_scheduled_executions", "public.solid_queue_jobs", column: "job_id", on_delete: :cascade

end
