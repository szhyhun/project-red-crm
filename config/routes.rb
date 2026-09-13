Rails.application.routes.draw do
  devise_for :users, skip: %i[sessions registrations passwords]

  root to: "rails/health#show"

  # Live updates for the portal: unread badges and new-message notices.
  mount ActionCable.server => "/cable"

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
        put "password", to: "passwords#update"
      end

      resources :products, only: %i[index show create update] do
        resources :components, only: %i[index create update destroy], controller: "product_components"
      end
      resources :taxes, only: %i[index create update destroy]
      resources :coupons, only: %i[index create update destroy]
      resources :travel_fees, only: %i[index create update destroy]
      resources :pricing_plans, only: %i[index create update destroy]
      get "listings/:listing_id/customer_access", to: "listing_customer_access#show"
      put "listings/:listing_id/customer_access", to: "listing_customer_access#update"
      resources :order_forms, only: %i[index create update destroy]
      resources :tags, only: %i[index create update destroy]
      put "client_accounts/:client_account_id/tags", to: "client_account_tags#update"
      resource :aryeo_integration, only: %i[show create destroy] do
        post :validate
        post :import
      end
      resources :orders, only: %i[index show create update] do
        resources :items, only: %i[create update destroy], controller: "order_items"
        post :cancel, on: :member
        post :approve, on: :member
        resources :deliverables, only: :index, controller: "order_deliverables"
      end
      resources :order_deliverables, only: %i[show update], controller: "order_deliverables"
      resources :invoices, only: %i[index create] do
        post :send_invoice, on: :member
        post :payment_intent, on: :member
        post :send_reminder, on: :member
      end
      get "portal/dashboard", to: "portal#dashboard"
      get "portal/listings", to: "portal#listings"
      get "portal/listings/:id", to: "portal#show_listing"
      get "portal/listings/:listing_id/media", to: "portal#listing_media"
      get "portal/listings/:listing_id/reviews", to: "media_reviews#listing_index"
      post "portal/listings/:listing_id/reviews", to: "media_reviews#create"
      get "portal/reviews/:id", to: "media_reviews#show"
      post "portal/reviews/:id/threads", to: "media_reviews#create_thread"
      post "portal/review_threads/:id/comments", to: "media_reviews#create_comment"
      post "portal/review_threads/:id/resolve", to: "media_reviews#resolve_thread"
      post "portal/review_threads/:id/reopen", to: "media_reviews#reopen_thread"
      patch "portal/review_comments/:id", to: "media_reviews#update_comment"
      delete "portal/review_comments/:id", to: "media_reviews#destroy_comment"
      post "portal/reviews/:id/submit", to: "media_reviews#submit"
      get "listings/:listing_id/media_reviews", to: "media_reviews#listing_index"
      get "media_reviews/:id", to: "media_reviews#show"
      post "media_review_threads/:id/comments", to: "media_reviews#create_comment"
      post "media_review_threads/:id/resolve", to: "media_reviews#resolve_thread"
      post "media_review_threads/:id/reopen", to: "media_reviews#reopen_thread"
      post "portal/listings", to: "portal#create_listing"
      post "portal/appointments/:id/reschedule", to: "portal#request_reschedule"
      post "portal/listings/:listing_id/deliverables/:deliverable_id/change_requests", to: "portal#create_change_request"
      resources :media_assets, only: %i[index create update destroy] do
        post :upload, on: :collection
        post :link, on: :collection
        post :reorder, on: :collection
        post :replace, on: :member
        post :retry, on: :member
        get :preview, on: :member
        get :download, on: :member
      end
      resources :conversations, only: %i[index show create update destroy] do
        post :messages, on: :member, action: :create_message
        resources :members, only: %i[create destroy], controller: "conversation_memberships"
      end
      post "conversations/reorder", to: "conversations#reorder"
      post "conversations/:conversation_id/messages/:message_id/attachments", to: "conversation_attachments#create"
      get "conversations/:conversation_id/messages/:message_id/attachments/:id/preview", to: "conversation_attachments#preview"
      get "conversations/:conversation_id/messages/:message_id/attachments/:id/download", to: "conversation_attachments#download"
      delete "conversations/:conversation_id/messages/:message_id/attachments/:id", to: "conversation_attachments#destroy"
      get "dashboard", to: "dashboard#show"
      resources :client_accounts, only: %i[index create update] do
        patch :billing, on: :member
        resource :archive, only: %i[create destroy], controller: "client_account_archives"
        resource :split, only: :create, controller: "client_account_splits"
        resource :summary, only: :show, controller: "client_account_summaries"
        resource :notifications, only: %i[show update], controller: "client_account_notifications"
        post :invite, on: :member
        resources :memberships, only: %i[index create], controller: "client_memberships"
      end
      resources :client_memberships, only: %i[update destroy] do
        post :accept, on: :member
        resource :invitation, only: :create, controller: "client_membership_invitations"
      end
      get "portal/memberships", to: "client_memberships#mine"
      post "portal/team_joins", to: "portal_team_joins#create"
      get "portal/order_form", to: "portal#order_form"
      get "portal/team_settings", to: "portal#team_settings"
      resource :profile, only: %i[show update], controller: "profile"
      resources :staff, only: %i[index create update], controller: "staff"
      resources :customer_users, only: %i[index show update] do
        get :work, on: :member
        post :password_reset, on: :member
        put :blocked_staff, on: :member
        resources :credit_transactions, only: %i[index create]
      end
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
      resources :workflow_tasks, only: %i[index show update destroy] do
        resources :comments, only: %i[create update destroy], controller: "task_comments"
        resources :checklist_items, only: %i[create update destroy], controller: "task_checklist_items"
      end
      post "workflow_tasks/:workflow_task_id/attachments", to: "board_attachments#create_task"
      post "workflow_tasks/:workflow_task_id/comments/:task_comment_id/attachments", to: "board_attachments#create_comment"
      get "workflow_tasks/:workflow_task_id/attachments/:id/preview", to: "board_attachments#preview"
      get "workflow_tasks/:workflow_task_id/attachments/:id/download", to: "board_attachments#download"
      delete "workflow_tasks/:workflow_task_id/attachments/:id", to: "board_attachments#destroy"
      resources :workflow_columns, only: %i[index create update destroy]
      resources :boards, only: %i[index show create update destroy] do
        resources :members, only: %i[index create update destroy], controller: "board_memberships"
        resources :labels, only: %i[index create update destroy], controller: "board_labels"
        resources :workflow_columns, only: %i[index create update destroy]
        resources :workflow_tasks, only: %i[index create]
        resources :workflows, only: %i[index show create update destroy], controller: "board_workflows"
        resources :workflow_runs, only: :index, controller: "board_workflow_runs" do
          post :retry, on: :member
        end
      end
      resources :user_groups, only: %i[index create update destroy] do
        resources :members, only: %i[create destroy], controller: "user_group_memberships"
      end
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
