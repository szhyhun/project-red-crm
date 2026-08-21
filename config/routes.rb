Rails.application.routes.draw do
  devise_for :users, skip: %i[sessions registrations passwords]

  root to: "rails/health#show"

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
      resources :taxes, only: %i[index create update destroy]
      resources :coupons, only: %i[index create update destroy]
      resources :travel_fees, only: %i[index create update destroy]
      resources :pricing_plans, only: %i[index create update destroy]
      resource :aryeo_integration, only: %i[show create destroy] do
        post :validate
        post :import
      end
      resources :orders, only: %i[index show create update] do
        resources :items, only: %i[create update destroy], controller: "order_items"
        post :cancel, on: :member
      end
      resources :invoices, only: %i[index create] do
        post :send_invoice, on: :member
        post :payment_intent, on: :member
        post :send_reminder, on: :member
      end
      get "client_portal", to: "client_portal#show"
      post "client_portal/appointments/:id/reschedule", to: "client_portal#request_reschedule"
      resources :media_assets, only: %i[index create update destroy] do
        post :upload, on: :collection
        post :link, on: :collection
        post :reorder, on: :collection
        post :replace, on: :member
        post :retry, on: :member
        get :preview, on: :member
        get :download, on: :member
      end
      resources :conversations, only: %i[index show create destroy] do
        post :messages, on: :member, action: :create_message
        resources :members, only: %i[create destroy], controller: "conversation_memberships"
      end
      get "dashboard", to: "dashboard#show"
      resources :client_accounts, only: %i[index create update] do
        post :invite, on: :member
      end
      resources :customer_teams, only: %i[index create update destroy] do
        resources :memberships, only: %i[create destroy], controller: "customer_team_memberships"
      end
      resources :staff, only: %i[index create update], controller: "staff"
      resources :listings, only: %i[index show create update] do
        get :download_media, on: :member
        resources :workflow_tasks, only: %i[index create]
        resources :appointments, only: :create
        resources :listing_assignments, only: %i[create destroy]
        resources :listing_notes, only: %i[create destroy]
        resources :payroll_items, only: :create
        resources :listing_feedbacks, only: :create
        resources :listing_customers, only: %i[create update destroy]
        resources :listing_custom_fields, only: %i[create update destroy]
        resources :marketing_materials, only: %i[create update destroy]
        resource :property_site, only: %i[show create update] do
          post :publish
        end
        resources :media_groups, only: %i[index create update destroy]
      end
      resources :appointments, only: %i[index update destroy]
      resources :appointments, only: [] do
        resources :team_members, only: %i[create destroy], controller: "appointment_team_members"
        resources :items, only: %i[create update destroy], controller: "appointment_items"
      end
      resources :payroll_items, only: %i[update destroy]
      resources :listing_feedbacks, only: :update
      resources :workflow_tasks, only: %i[index update destroy]
      resources :workflow_columns, only: %i[index create update destroy]
      resources :saved_listing_views, only: %i[index create update destroy] do
        patch :preference, on: :collection
      end

      namespace :webhooks do
        post :stripe, to: "stripe#create"
      end

      namespace :public do
        get "property_sites/:organization_slug/:slug", to: "property_sites#show"
      end
    end
  end
end
