Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Webhooks
  namespace :webhooks do
    get  "whatsapp", to: proc { [200, {}, ["OK"]] }
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
    member do
      patch :cancel
      patch :confirm
    end
  end
  resources :patients, only: [ :index, :show, :create, :update, :destroy ]
  resources :conversations, only: [ :index, :show ] do
    collection do
      post :import
      get :export_tagged
    end
    member do
      post :reply
      patch :update_tags
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
  get   "settings",          to: "settings#index"
  post  "settings/language", to: "settings#update_language"
  patch "settings/practice", to: "settings#update_practice", as: :settings_practice
  patch "settings/pricing",  to: "settings#update_pricing",  as: :settings_pricing

  # Error pages — matched by exceptions_app when Rails catches a routing/HTTP error
  match "/404", to: "errors#not_found",    via: :all
  match "/422", to: "errors#unprocessable", via: :all
  match "/500", to: "errors#server_error",  via: :all
end
