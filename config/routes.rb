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
      resources :media_assets, only: %i[index create update]
      resources :conversations, only: %i[index show create] do
        post :messages, on: :member, action: :create_message
      end
      get "dashboard", to: "dashboard#show"
      resources :client_accounts, only: %i[index create] do
        post :invite, on: :member
      end
      resources :staff, only: %i[index create], controller: "staff"
      resources :listings, only: %i[index show create update] do
        resources :workflow_tasks, only: %i[index create]
        resources :appointments, only: :create
        resources :listing_assignments, only: %i[create destroy]
        resource :property_site, only: %i[show create update] do
          post :publish
        end
      end
      resources :appointments, only: %i[index update]
      resources :workflow_tasks, only: %i[index update]

      namespace :public do
        get "property_sites/:organization_slug/:slug", to: "property_sites#show"
      end
    end
  end
end
