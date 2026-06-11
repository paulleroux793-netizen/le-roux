Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Deeper readiness probe (also checks the DB) for external uptime monitors — see
  # HealthController. No auth; exposes only system status, never patient data.
  get "health"  => "health#show"
  get "healthz" => "health#show"

  # POPIA s23 data-subject access export (JSON of everything held on a patient).
  get "patients/:patient_id/data_export" => "data_exports#show", as: :patient_data_export

  # Lab-case worklist (read-only; cases are sent/returned via the existing
  # PATCH /treatment_items/:id controls on the treatment plan).
  get "lab" => "lab_cases#index", as: :lab

  # Per-user auth (active only when USER_AUTH_ENABLED). Login screen + session create/destroy.
  get    "login"  => "sessions#new",     as: :login
  post   "login"  => "sessions#create"
  delete "logout" => "sessions#destroy", as: :logout

  # Webhooks
  namespace :webhooks do
    get  "whatsapp", to: proc { [ 200, {}, [ "OK" ] ] }
    post "whatsapp", to: "whatsapp#incoming"

    # Voice call webhooks
    post "voice",                     to: "voice#incoming"
    post "voice/gather",              to: "voice#gather"
    post "voice/status",              to: "voice#status"
    post "voice/confirmation",        to: "voice#confirmation"
    post "voice/confirmation_gather", to: "voice#confirmation_gather"
  end

  # Dashboard
  root "pages#dashboard"
  get "dashboard", to: "pages#dashboard"

  # Dashboard pages
  resources :appointments, only: [ :index, :show, :create, :update, :destroy ] do
    collection do
      # Dedicated full-screen calendar page — just the week grid with the
      # dentist name at the top, no dashboard chrome / stat cards.
      get :calendar
      # Next-available open slots for a provider+duration (booking-speed finder, JSON).
      get :next_available
    end
    member do
      patch :cancel
      patch :confirm
      patch :set_status
      post  :whatsapp_pack     # send the 4 standard WhatsApp messages (location/directions/intake/confirmation)
      post  :whatsapp_confirm  # send just the booking confirmation (date/time)
    end
  end
  # Elixir-style two-column day diary (one column per dentist).
  get "diary", to: "appointments#diary", as: :diary
  # Printable day schedule (Elixir "APPOINTMENT DETAILS" layout) for the WhatsApp group.
  get "diary/print", to: "appointments#print_schedule", as: :diary_print

  # Server-side Open-Graph link preview for the chat bubbles (SSRF-guarded). GET /link_preview?url=
  get "link_preview", to: "link_previews#show"

  # Diary reminders / notes (non-appointment calendar items)
  resources :calendar_notes, only: [ :create, :update, :destroy ]

  resources :patients, only: [ :index, :show, :create, :update, :destroy ] do
    collection { get :lookup } # type-ahead search (JSON) for the booking modal
    member do
      post :merge_into   # merge a self-registered placeholder into an existing patient
      post :confirm_new  # confirm a self-registration is genuinely a new patient
    end
  end
  resources :conversations, only: [ :index, :show ] do
    collection do
      post :import
      get :export_tagged
    end
    member do
      post :reply
      post :forward         # forward a message from this chat to another WhatsApp conversation
      patch :update_tags
      patch :resume_ai
    end
  end
  get "search", to: "search#index"

  # Pre-appointment reminders dashboard (Phase 9.6 sub-area #7)
  get  "reminders", to: "reminders#index"
  post "reminders/:appointment_id/send",
       to: "reminders#send_reminder",
       as: :send_reminder

  resources :notifications, only: [ :index ] do
    member do
      patch :mark_read
    end
    collection do
      post :mark_all_read
    end
  end
  get "analytics", to: "analytics#index"
  get "audit-log", to: "audit_logs#index", as: :audit_log
  get "audit-log/export", to: "audit_logs#export", as: :audit_log_export

  # Daily Reconciliation — the Elixir-vs-Ivory learning-loop dashboard.
  # Compares what Elixir actually delivered today against what Ivory
  # predicted, and suggests specific improvements (2026-05-27 directive).
  get  "reconciliation",      to: "reconciliation#index", as: :reconciliation
  post "reconciliation/scan", to: "reconciliation#scan",  as: :reconciliation_scan

  # ── Practice-management system (Phase 1+) — ADDITIVE, read-first ──
  get   "procedure-codes",            to: "procedure_codes#index", as: :procedure_codes
  post  "procedure-codes",            to: "procedure_codes#create"
  post  "procedure-codes/bulk-uplift", to: "procedure_codes#bulk_update", as: :procedure_codes_bulk_uplift
  # Staff can edit description, fee, category + VAT inline; add codes; bulk-uplift fees.
  patch "procedure-codes/:id",        to: "procedure_codes#update", as: :procedure_code
  get "treatment-macros", to: "treatment_macros#index", as: :treatment_macros
  resources :billing_accounts, only: [ :index, :show ], path: "accounts" do
    member do
      get  :statement        # /accounts/:id/statement(.pdf)?from=&to= — date-range statement
      post :receive_payment  # one payment allocated across the account's open invoices
      post :deposit          # advance deposit, banked as account credit
      post :apply_credit     # apply available credit onto an invoice
      post :refund           # pay available credit back to the patient
    end
  end
  resources :courses_of_treatment, only: [ :index, :show ], path: "courses-of-treatment" do
    collection do
      # P9.3 — clickable odontogram → chart entry + planned procedure
      post :chart_quick_add
    end
    member do
      # R1.2 — add a procedure to this COT (no tooth required)
      post :add_item
      # R1.3 — convert this COT into an Estimate or Invoice
      post :generate_estimate
      post :generate_invoice
      # C4 — apply a visit-type template (TreatmentMacro) in one click
      post :apply_macro
      # Set the treating dentist on this COT (carries to generated invoice/estimate)
      patch :set_provider
    end
  end

  # R1.1 — let staff mark individual treatment items done / failed / voided
  resources :treatment_items, only: [ :update ]

  # Start a fresh blank estimate for a patient (reception/dentist quoting flow),
  # then add line items in the editor. R1.3b.
  post "patients/:patient_id/estimates", to: "estimates#create", as: :patient_estimates
  # Start a fresh treatment plan (Course of Treatment) for a patient, then add items.
  post "patients/:patient_id/courses_of_treatment", to: "courses_of_treatment#create", as: :patient_courses_of_treatment
  resources :estimates, only: [ :index, :show, :update ] do
    member do
      # R1.4 — convert estimate to invoice
      post :accept_and_invoice
      # C1 — drag-drop file attachments on the estimate (X-ray screenshots etc)
      post :upload_attachment
      delete "attachments/:attachment_id", to: "estimates#delete_attachment", as: :attachment
      # Visit bundle — add a whole macro (e.g. "New patient exam") to the estimate in one click.
      post :apply_macro
      # AI compose — free-text treatment description → auto-populated coded lines (per tooth).
      post :ai_compose
    end
    # Editable line items — add/amend codes, teeth, fees on an estimate.
    resources :lines, only: [ :create ], controller: "estimate_lines"
  end
  patch  "estimate_lines/:id", to: "estimate_lines#update",  as: :estimate_line
  delete "estimate_lines/:id", to: "estimate_lines#destroy"

  resources :invoices, only: [ :index, :show ] do
    # R1.5 — record a payment (card / cash / EFT) against an invoice
    resources :payments, only: [ :create ]
    member { post :write_off }  # clear bad debt off the books (status → written_off)
  end
  get  "payments/:id/receipt", to: "payments#receipt", as: :payment_receipt  # printable receipt PDF
  post "payments/:id/reverse", to: "payments#reverse", as: :reverse_payment  # undo a mis-keyed/refunded payment
  get "patients/:patient_id/file", to: "patient_files#show", as: :patient_file
  # Staff: send the WhatsApp intake link, and print the completed pack on arrival.
  post "patients/:patient_id/send-intake", to: "patient_files#send_intake", as: :send_patient_intake
  get  "patients/:patient_id/intake.pdf", to: "patient_files#intake_pdf",  as: :patient_intake_pdf, format: false

  # ── Public, tokenised patient intake wizard (UNAUTHENTICATED — see PublicController) ──
  # The signed_id link is sent over WhatsApp; no PII in the URL, 14-day expiry.
  get   "intake/:token", to: "intakes#show",   as: :intake
  match "intake/:token", to: "intakes#update", via: %i[patch put]
  get  "imaging",      to: "imaging#index", as: :imaging
  post "imaging/scan", to: "imaging#scan",  as: :imaging_scan
  get  "imaging/:id/image", to: "imaging#image", as: :imaging_image
  get  "imaging/:id/dicom", to: "imaging#dicom", as: :imaging_dicom
  resources :scribe_sessions, only: [ :index, :show ], path: "scribe-sessions"

  # N1 — Admin-only management of recording devices (Surgery 1 / Reception …)
  namespace :admin do
    resources :recording_devices, path: "recording-devices"
  end

  # N2 — Unified inbox (Outlook-style). Provider OAuth flows land later.
  get  "mail",                to: "mail#index", as: :mail
  patch "mail/threads/:id/mark_read", to: "mail#mark_read", as: :mail_thread_mark_read
  post  "mail/threads/:id/reply",     to: "mail#reply",     as: :mail_thread_reply
  patch "mail/threads/:id/trash",     to: "mail#trash",     as: :mail_thread_trash

  # 2026-05-24 — Always-on scribe daemon (Phase 1 = practice-PC).
  # The Python daemon at tools/scribe-daemon/ POSTs transcript chunks
  # here authenticated by X-Scribe-Token (env SCRIBE_API_TOKEN).
  namespace :api do
    namespace :v1 do
      post "scribe/transcript", to: "scribe#transcript"
      get  "scribe/heartbeat",  to: "scribe#heartbeat"
      # Website chat-widget booking endpoint — same booking brain as WhatsApp.
      # INERT unless WEB_CHAT_ENABLED=true (controller returns 404). CORS-gated.
      post  "web_chat", to: "web_chat#create"
      match "web_chat", to: "web_chat#preflight", via: :options
    end
  end

  # Internal preview of the website chat widget (no login, no PHI) so Paul/SEO can
  # talk to it before the public embed. Loads /web-chat-widget.js + the API above.
  get "web_chat_preview", to: "web_chat_preview#show"
  get   "recalls", to: "recalls#index", as: :recalls
  patch "recalls/:id", to: "recalls#update", as: :recall  # reception works the list (contacted/booked/done)
  get "reporting", to: "reporting#index", as: :reporting
  # Cash-up / transaction report (day|month|year) — HTML, CSV (Excel) or PDF.
  get "reporting/transactions", to: "reporting#transactions", as: :reporting_transactions
  get   "settings",          to: "settings#index"
  post  "settings/language", to: "settings#update_language"
  patch "settings/practice", to: "settings#update_practice", as: :settings_practice
  patch "settings/billing",  to: "settings#update_billing",  as: :settings_billing
  patch "settings/pricing",  to: "settings#update_pricing",  as: :settings_pricing

  # Public MP3 endpoint Twilio fetches via TwiML <Play>. Serves cached audio
  # generated by ElevenLabsService; missing or invalid hashes return 404.
  get "/voice/audio/:hash.mp3", to: "voice_audio#show", as: :voice_audio, format: false

  # Self-hosted Pipecat voice agent (separate process on the rig). INERT unless
  # VOICE_AGENT_ENABLED=true; token-gated. Single-source prompt fetch (no PHI).
  get "/voice_agent/prompt", to: "voice_agent#prompt"
  # (next cycle) post "/voice_agent/availability"; post "/voice_agent/booking" — reuse AvailabilityService + booking path

  # Error pages — matched by exceptions_app when Rails catches a routing/HTTP error
  match "/404", to: "errors#not_found",    via: :all
  match "/422", to: "errors#unprocessable", via: :all
  match "/500", to: "errors#server_error",  via: :all
end
