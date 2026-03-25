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

  # OmniAuth routes
  get "/auth/:provider/callback", to: "auth/omniauth_callbacks#slack", as: :auth_provider_callback
  get "/auth/failure", to: "auth/omniauth_callbacks#failure"

  # Authenticated routes
  get "/dashboard", to: "dashboard#index", as: :dashboard
  get "/settings", to: "settings#index", as: :settings

  resources :webhooks, except: [ :edit ] do
    member do
      post :test
      post :activate
      post :deactivate
    end
    get :sample_payload, on: :collection
    resources :deliveries, only: [ :index, :show ], controller: "webhook_deliveries"
  end
end
