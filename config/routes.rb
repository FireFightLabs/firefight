Rails.application.routes.draw do
  # Redirect to localhost from 127.0.0.1 to use same IP address with Vite server
  constraints(host: "127.0.0.1") do
    get "(*path)", to: redirect { |params, req| "#{req.protocol}localhost:#{req.port}/#{params[:path]}" }
  end

  # Health check
  get "up" => "rails/health#show", as: :rails_health_check

  # API routes
  namespace :api do
    namespace :v1 do
      post "commands", to: "commands#create"
      post "interactions", to: "interactions#create"
      post "events", to: "events#create"

      # Public API (Bearer token auth)
      resources :incidents, only: [ :index, :show, :create, :update ]
      resources :severities, only: [ :index ]
      resources :statuses, only: [ :index ]
      resources :incident_types, only: [ :index ]
    end
  end

  # Public routes
  root to: "sessions#new"
  get "/login", to: "sessions#new", as: :login
  delete "/logout", to: "sessions#destroy", as: :logout

  # OmniAuth callbacks — explicit per-strategy so each maps to its own action.
  get "/auth/slack_openid/callback", to: "auth/omniauth_callbacks#slack_openid", as: :slack_openid_callback
  get "/auth/slack/callback",        to: "auth/omniauth_callbacks#slack",        as: :slack_install_callback
  get "/auth/failure",               to: "auth/omniauth_callbacks#failure"

  # Onboarding pages between OIDC sign-in and dashboard access
  get "/onboarding/install", to: "onboarding#install", as: :onboarding_install
  get "/onboarding/welcome", to: "onboarding#welcome", as: :onboarding_welcome

  # Authenticated application routes
  scope :app do
    get "/", to: "dashboard#index", as: :dashboard
    get "/settings", to: "settings#index", as: :settings
    get "/settings/roles", to: "settings#roles", as: :settings_roles
    get "/settings/statuses", to: "settings#statuses", as: :settings_statuses
    get "/settings/severities", to: "settings#severities", as: :settings_severities
    get "/settings/types", to: "settings#types", as: :settings_types
    resources :incident_types, only: [ :create, :update, :destroy ], path: "settings/types"
    get "/settings/custom-fields", to: "settings#custom_fields", as: :settings_custom_fields
    get "/settings/forms", to: "settings#forms", as: :settings_forms
    get "/settings/webhooks", to: "settings#webhooks", as: :settings_webhooks
    get "/settings/api-keys", to: "settings#api_keys", as: :settings_api_keys
    resources :api_keys, only: [ :create, :update, :destroy ], path: "settings/api-keys"
    resources :incident_severities, only: [ :create, :update, :destroy ], path: "settings/severities" do
      member do
        patch :disable
        patch :enable
      end
    end
    resources :incident_statuses, only: [ :create, :update, :destroy ], path: "settings/statuses" do
      member do
        patch :disable
        patch :enable
      end
    end
    resources :incident_roles, only: [ :create, :destroy ], path: "settings/roles" do
      member do
        patch :disable
        patch :enable
      end
    end
    resources :incident_field_definitions, only: [ :create, :update ], path: "settings/custom-fields"
    resources :incident_form_fields, only: [ :create, :update, :destroy ], path: "settings/forms/fields" do
      collection do
        patch :reorder
      end
      member do
        patch :move_up
        patch :move_down
      end
    end
    get "/incidents/:id", to: "incidents#show", as: :incident
    get "/incidents/:incident_id/postmortem", to: "incidents#postmortem", as: :incident_postmortem
    patch "/incidents/:incident_id/postmortem", to: "incidents#update_postmortem"
    patch "/incidents/:incident_id/postmortem/status", to: "incidents#update_postmortem_status", as: :incident_postmortem_status
    get "/incidents/:incident_id/postmortem/revisions", to: "incidents#postmortem_revisions", as: :incident_postmortem_revisions
    get "/catalogue", to: "catalogue#index", as: :catalogue
    get "/catalogue/:type_slug", to: "catalogue#show", as: :catalogue_type
    post "/catalogue/types", to: "catalogue#create_type"
    patch "/catalogue/types/:id", to: "catalogue#update_type"
    delete "/catalogue/types/:id", to: "catalogue#destroy_type"
    post "/catalogue/:type_slug/entries", to: "catalogue#create_entry"
    patch "/catalogue/entries/:id", to: "catalogue#update_entry"
    delete "/catalogue/entries/:id", to: "catalogue#destroy_entry"
    get "/catalogue/search/members", to: "catalogue#search_members"
    get "/catalogue/search/channels", to: "catalogue#search_channels"

    resources :webhooks, only: [ :create, :update, :destroy ] do
      member do
        post :test
        post :activate
        post :deactivate
      end
      get :sample_payload, on: :collection
    end

    get "/settings/members", to: "settings#members", as: :settings_members
  end
end
