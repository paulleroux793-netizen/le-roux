Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

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
  resources :appointments, only: [ :index, :show, :create, :update ] do
    collection do
      # Dedicated full-screen calendar page — just the week grid with the
      # dentist name at the top, no dashboard chrome / stat cards.
      get :calendar
    end
    member do
      patch :cancel
      patch :confirm
      patch :set_status
    end
  end
  # Elixir-style two-column day diary (one column per dentist).
  get "diary", to: "appointments#diary", as: :diary

  # Diary reminders / notes (non-appointment calendar items)
  resources :calendar_notes, only: [ :create, :update, :destroy ]

  resources :patients, only: [ :index, :show, :create, :update, :destroy ] do
    collection { get :lookup } # type-ahead search (JSON) for the booking modal
  end
  resources :conversations, only: [ :index, :show ] do
    collection do
      post :import
      get :export_tagged
    end
    member do
      post :reply
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
  get   "procedure-codes",     to: "procedure_codes#index", as: :procedure_codes
  # P9.6 — let staff fix bad descriptions inline. Only :description is editable.
  patch "procedure-codes/:id", to: "procedure_codes#update", as: :procedure_code
  get "treatment-macros", to: "treatment_macros#index", as: :treatment_macros
  resources :billing_accounts, only: [ :index, :show ], path: "accounts"
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
    end
  end

  # R1.1 — let staff mark individual treatment items done / failed / voided
  resources :treatment_items, only: [ :update ]

  resources :estimates, only: [ :index, :show ] do
    member do
      # R1.4 — convert estimate to invoice
      post :accept_and_invoice
      # C1 — drag-drop file attachments on the estimate (X-ray screenshots etc)
      post :upload_attachment
      delete "attachments/:attachment_id", to: "estimates#delete_attachment", as: :attachment
    end
  end

  resources :invoices, only: [ :index, :show ] do
    # R1.5 — record a payment (card / cash / EFT) against an invoice
    resources :payments, only: [ :create ]
  end
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
  resources :scribe_sessions, only: [ :index, :show ], path: "scribe-sessions"

  # N1 — Admin-only management of recording devices (Surgery 1 / Reception …)
  namespace :admin do
    resources :recording_devices, path: "recording-devices"
  end

  # N2 — Unified inbox (Outlook-style). Provider OAuth flows land later.
  get  "mail",                to: "mail#index", as: :mail
  patch "mail/threads/:id/mark_read", to: "mail#mark_read", as: :mail_thread_mark_read

  # 2026-05-24 — Always-on scribe daemon (Phase 1 = practice-PC).
  # The Python daemon at tools/scribe-daemon/ POSTs transcript chunks
  # here authenticated by X-Scribe-Token (env SCRIBE_API_TOKEN).
  namespace :api do
    namespace :v1 do
      post "scribe/transcript", to: "scribe#transcript"
      get  "scribe/heartbeat",  to: "scribe#heartbeat"
    end
  end
  get "recalls", to: "recalls#index", as: :recalls
  get "reporting", to: "reporting#index", as: :reporting
  get   "settings",          to: "settings#index"
  post  "settings/language", to: "settings#update_language"
  patch "settings/practice", to: "settings#update_practice", as: :settings_practice
  patch "settings/pricing",  to: "settings#update_pricing",  as: :settings_pricing

  # Public MP3 endpoint Twilio fetches via TwiML <Play>. Serves cached audio
  # generated by ElevenLabsService; missing or invalid hashes return 404.
  get "/voice/audio/:hash.mp3", to: "voice_audio#show", as: :voice_audio, format: false

  # Error pages — matched by exceptions_app when Rails catches a routing/HTTP error
  match "/404", to: "errors#not_found",    via: :all
  match "/422", to: "errors#unprocessable", via: :all
  match "/500", to: "errors#server_error",  via: :all
end
