Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Webhooks
  namespace :webhooks do
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
  resources :appointments, only: [:index, :show, :create, :update] do
    member do
      patch :cancel
      patch :confirm
    end
  end
  resources :patients, only: [:index, :show, :create, :update]
  resources :conversations, only: [:index, :show] do
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

  resources :notifications, only: [:index] do
    member do
      patch :mark_read
    end
    collection do
      post :mark_all_read
    end
  end
  get "analytics", to: "analytics#index"
  get "settings", to: "settings#index"
  post "settings/language", to: "settings#update_language"
end
