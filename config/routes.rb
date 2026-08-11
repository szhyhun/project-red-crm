Rails.application.routes.draw do
  devise_for :users, skip: %i[sessions registrations passwords]

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  namespace :api do
    namespace :v1 do
      namespace :auth do
        get "csrf", to: "sessions#csrf"
        post "sign_up", to: "registrations#create"
        post "sign_in", to: "sessions#create"
        delete "sign_out", to: "sessions#destroy"
        get "me", to: "sessions#show"
      end

      resources :products, only: %i[index show create update]
      resources :orders, only: %i[index show create update]
      resources :invoices, only: %i[index create]
      get "dashboard", to: "dashboard#show"
      resources :client_accounts, only: %i[index create]
      resources :staff, only: :index, controller: "staff"
      resources :listings, only: %i[index show create update] do
        resources :workflow_tasks, only: %i[index create]
        resources :appointments, only: :create
        resources :listing_assignments, only: %i[create destroy]
      end
      resources :appointments, only: %i[index update]
      resources :workflow_tasks, only: %i[index update]
    end
  end
end
