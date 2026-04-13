Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Webhooks
  namespace :webhooks do
    post "whatsapp", to: "whatsapp#incoming"
  end

  # Dashboard
  root "pages#dashboard"
  get "dashboard", to: "pages#dashboard"

  # Dashboard pages
  resources :appointments, only: [:index, :show]
  resources :patients, only: [:index, :show]
  resources :conversations, only: [:index, :show]
  get "analytics", to: "analytics#index"
  get "settings", to: "settings#index"
end
