Rails.application.routes.draw do
  # Redirect to localhost from 127.0.0.1 to use same IP address with Vite server.
  # Development only, in production this catch-all 301s the internal health
  # check (Northflank probes http://127.0.0.1:3000/up), marking the pod unhealthy.
  if Rails.env.development?
    constraints(host: "127.0.0.1") do
      get "(*path)", to: redirect { |params, req| "#{req.protocol}localhost:#{req.port}/#{params[:path]}" }
    end
  end

  # Health check
  get "up" => "rails/health#show", as: :rails_health_check

  # API routes
  namespace :api do
    namespace :v1 do
      post "commands", to: "commands#create"
      post "interactions", to: "interactions#create"
      post "events", to: "events#create"

      # Alert ingest (per-source secret auth via provider adapter)
      post "alerts/:endpoint_path", to: "alerts#create", as: :alert_ingest

      # Public API (Bearer token auth)
      resources :incidents, only: [ :index, :show, :create, :update ] do
        resources :timeline, only: [ :index ], controller: "timeline" do
          member do
            patch :dismiss
          end
        end
        resources :action_items, only: [ :index, :create, :update ]
        # Taking part in an incident rather than moving it: everything a person
        # can do from Slack short of changing the status.
        member do
          post :escalate, to: "incident_participation#escalate"
          post :invite, to: "incident_participation#invite"
          post :link, to: "incident_participation#link"
          post :shoutout, to: "incident_participation#shoutout"
          post "runbook_steps/claim", to: "incident_participation#claim_runbook_step", as: :claim_runbook_step
        end
      end
      # Configuring the workspace over REST, matching the MCP tools. Options are
      # addressed by slug, which is the handle stored records refer to.
      resources :severities, only: [ :index, :create, :update, :destroy ]
      resources :statuses, only: [ :index, :create, :update, :destroy ]
      resources :incident_types, only: [ :index, :create, :update, :destroy ]
      resources :incident_roles, only: [ :index, :create, :update, :destroy ]
      resources :alert_sources, only: [ :index, :create, :update, :destroy ]
      resources :webhooks, only: [ :index, :create, :update, :destroy ]
      resources :api_keys, only: [ :index, :create, :update, :destroy ]
      resources :agents, only: [ :index, :create, :update, :destroy ] do
        member do
          post :rotate
          delete "tokens/:token_prefix", action: :revoke_token, as: :token
        end
      end
      resources :custom_fields, only: [ :index ]
      resources :runbooks, only: [ :index, :show ]

      resources :abilities, only: [ :index ]
      resources :principals, only: [ :index ]
      resources :permission_sets, only: [ :index, :create, :update, :destroy ]
      resources :grants, only: [ :index, :create, :update, :destroy ]
      resources :approval_rules, only: [ :index, :create, :update, :destroy ] do
        member do
          post :move_up
          post :move_down
        end
      end
      resources :approvals, only: [ :index, :show ] do
        member do
          post :approve
          post :deny
        end
      end
      get "activity", to: "activity#index", as: :activity

      namespace :catalog do
        get "types", to: "types#index", as: :types
        get "types/:slug", to: "types#show", as: :type
        get "types/:slug/entries", to: "entries#index", as: :type_entries
        post "types/:slug/entries", to: "entries#create"
        get "entries/:id", to: "entries#show", as: :entry
        patch "entries/:id", to: "entries#update"
        delete "entries/:id", to: "entries#destroy"
      end
    end
  end

  # OAuth 2.1 provider for MCP clients: authorize/token/revoke from Doorkeeper,
  # discovery metadata (RFC 8414/9728) and dynamic client registration
  # (RFC 7591) are ours. No application-management UI is exposed.
  use_doorkeeper do
    skip_controllers :applications, :authorized_applications
  end
  post "/oauth/register", to: "oauth/registrations#create", as: :oauth_register
  get "/.well-known/oauth-authorization-server", to: "oauth/metadata#authorization_server"
  get "/.well-known/oauth-protected-resource", to: "oauth/metadata#protected_resource"
  get "/.well-known/oauth-protected-resource/mcp", to: "oauth/metadata#protected_resource"

  # MCP server (stateless Streamable HTTP, Bearer ApiKey auth)
  post "/mcp", to: "mcp#create", as: :mcp
  match "/mcp", to: "mcp#method_not_allowed", via: [ :get, :delete, :put, :patch ]

  # Public routes
  root to: "sessions#new"
  get "/login", to: "sessions#new", as: :login
  delete "/logout", to: "sessions#destroy", as: :logout
  post "/invite-code/claim", to: "invite_codes#create", as: :claim_invite_code

  # OmniAuth callbacks, explicit per-strategy so each maps to its own action.
  get "/auth/slack_openid/callback", to: "auth/omniauth_callbacks#slack_openid", as: :slack_openid_callback
  get "/auth/slack/callback",        to: "auth/omniauth_callbacks#slack",        as: :slack_install_callback
  get "/auth/failure",               to: "auth/omniauth_callbacks#failure"

  # OmniAuth start endpoints. The OmniAuth middleware intercepts these before
  # Rails routing, these declarations exist only so we get named path helpers.
  # The redirect target is a safety net in case the middleware is misconfigured.
  get "/auth/slack_openid", to: redirect("/login"), as: :sign_in_with_slack
  get "/auth/slack",        to: redirect("/login"), as: :install_slack_app

  # Onboarding pages between OIDC sign-in and dashboard access
  get "/onboarding/invite-code", to: "onboarding#invite_code", as: :onboarding_invite_code
  get "/onboarding/install", to: "onboarding#install", as: :onboarding_install
  get "/onboarding/reinstall", to: "onboarding#reinstall", as: :onboarding_reinstall
  get "/onboarding/welcome", to: "onboarding#welcome", as: :onboarding_welcome

  # Authenticated application routes
  scope :app do
    get "/", to: "dashboard#index", as: :dashboard
    post "/workspace-switch", to: "workspace_switches#create", as: :workspace_switch
    get "/settings", to: "settings#index", as: :settings
    get "/settings/roles", to: "settings#roles", as: :settings_roles
    get "/settings/statuses", to: "settings#statuses", as: :settings_statuses
    get "/settings/severities", to: "settings#severities", as: :settings_severities
    get "/settings/types", to: "settings#types", as: :settings_types
    resources :incident_types, only: [ :create, :update, :destroy ], path: "settings/types" do
      collection do
        patch :reorder
      end
      member do
        patch :disable
        patch :enable
      end
    end
    get "/settings/runbooks", to: "settings#runbooks", as: :settings_runbooks
    resources :runbooks, only: [ :create, :update, :destroy ], path: "settings/runbooks" do
      collection do
        patch :reorder
      end
      member do
        patch :disable
        patch :enable
      end
    end
    get "/settings/custom-fields", to: "settings#custom_fields", as: :settings_custom_fields
    get "/settings/forms", to: "settings#forms", as: :settings_forms
    get "/developer/webhooks", to: "settings#webhooks", as: :developer_webhooks
    get "/settings/alert-sources", to: "settings#alert_sources", as: :settings_alert_sources
    resources :alert_sources, only: [ :create, :update, :destroy ], path: "settings/alert-sources" do
      member do
        post :token
        get :sample_payload
      end
    end
    get "/settings/alerts", to: "settings#alerts", as: :settings_alerts
    get "/settings/alert-routing", to: "settings#alert_routing", as: :settings_alert_routing
    patch "/settings/alert-routing", to: "alert_routing#update", as: :alert_routing
    post "/settings/alert-routing/test", to: "alert_routing#test", as: :alert_routing_test
    post "/settings/alert-routing/send-test", to: "alert_routing#send_test", as: :alert_routing_send_test
    resources :policy_rules, only: [ :create, :update, :destroy ], path: "settings/alert-routing/rules" do
      member do
        patch :move_up
        patch :move_down
      end
    end
    get "/developer/api-keys", to: "settings#api_keys", as: :developer_api_keys
    delete "/developer/connected-agents/:id", to: "connected_agents#destroy", as: :connected_agent
    resources :api_keys, only: [ :create, :update, :destroy ], path: "developer/api-keys" do
      member do
        get :abilities
      end
    end
    resources :integrations, only: [ :index, :create, :destroy ] do
      member do
        post :sync
        patch :toggle_tool
        patch :set_all_tools
        patch :toggle
        patch :retarget_environment
      end
      collection do
        get :oauth_start
        get "oauth/callback", action: :oauth_callback, as: :oauth_callback
      end
    end
    get "/gateway/permissions", to: "settings#permissions", as: :gateway_permissions
    resources :ability_grants, only: [ :create, :update, :destroy ], path: "gateway/permissions/grants"
    resources :ability_roles, only: [ :create, :update, :destroy ], path: "gateway/permissions/sets"
    resources :approval_rules, only: [ :create, :update, :destroy ], path: "gateway/permissions/approval-rules" do
      member do
        patch :move_up
        patch :move_down
      end
    end
    resources :agents, only: [ :index, :create, :update, :destroy ], path: "gateway/agents", as: :gateway_agents do
      member do
        post :rotate
      end
    end
    # An agent's tokens are its own business, managed where the agent is rather
    # than alongside the workspace's developer keys.
    delete "/gateway/agents/:agent_id/tokens/:id", to: "agent_tokens#destroy", as: :gateway_agent_token
    get "/gateway/activity", to: "settings#activity", as: :gateway_activity
    get "/gateway/approvals", to: "settings#approvals", as: :gateway_approvals
    resources :approvals, only: [], path: "gateway/approvals" do
      member do
        post :approve
        post :deny
      end
    end
    resources :incident_severities, only: [ :create, :update, :destroy ], path: "settings/severities" do
      collection do
        patch :reorder
      end
      member do
        patch :disable
        patch :enable
        patch :make_default
      end
    end
    resources :incident_statuses, only: [ :create, :update, :destroy ], path: "settings/statuses" do
      collection do
        patch :reorder
      end
      member do
        patch :disable
        patch :enable
        patch :make_default
      end
    end
    resources :incident_roles, only: [ :create, :update, :destroy ], path: "settings/roles" do
      collection do
        patch :reorder
      end
      member do
        patch :disable
        patch :enable
      end
    end
    resources :incident_field_definitions, only: [ :create, :update, :destroy ], path: "settings/custom-fields" do
      member do
        patch :disable
        patch :enable
      end
    end
    resources :incident_form_fields, only: [ :create, :update, :destroy ], path: "settings/forms/fields" do
      collection do
        patch :reorder
      end
      member do
        patch :move_up
        patch :move_down
      end
    end
    post "/incidents/:incident_id/actions", to: "incident_actions#create", as: :incident_actions
    patch "/incidents/:incident_id/actions/:id/pick_up", to: "incident_actions#pick_up", as: :pick_up_incident_action
    patch "/incidents/:incident_id/actions/:id/assign", to: "incident_actions#assign", as: :assign_incident_action
    patch "/incidents/:incident_id/actions/:id/complete", to: "incident_actions#complete", as: :complete_incident_action
    post "/incidents/:incident_id/runbooks/:incident_runbook_id/steps/:step_id/claim", to: "incident_runbooks#claim_step", as: :claim_runbook_step
    post "/incidents/:incident_id/runbooks", to: "incident_runbooks#create", as: :incident_runbooks
    patch "/incidents/:incident_id/events/:id/dismiss", to: "incident_events#dismiss", as: :dismiss_incident_event
    get "/incidents/declare/form", to: "incident_lifecycle#declare_form", as: :declare_incident_form
    post "/incidents/declare", to: "incident_lifecycle#declare", as: :declare_incident
    get "/incidents/:incident_id/form/:form", to: "incident_lifecycle#form", as: :incident_form
    patch "/incidents/:incident_id/form/:form", to: "incident_lifecycle#update", as: :incident_lifecycle
    patch "/incidents/:incident_id/role", to: "incident_lifecycle#assign_role", as: :assign_incident_role
    patch "/incidents/:incident_id/reopen", to: "incident_lifecycle#reopen", as: :incident_reopen
    post "/incidents/:incident_id/link", to: "incident_lifecycle#link", as: :incident_link
    post "/incidents/:incident_id/escalate", to: "incident_participation#escalate", as: :incident_escalate
    post "/incidents/:incident_id/invite", to: "incident_participation#invite", as: :incident_invite
    post "/incidents/:incident_id/shoutout", to: "incident_participation#shoutout", as: :incident_shoutout
    get "/incidents/:id", to: "incidents#show", as: :incident
    get "/incidents/:incident_id/postmortem", to: "incidents#postmortem", as: :incident_postmortem
    patch "/incidents/:incident_id/postmortem", to: "incidents#update_postmortem"
    post "/incidents/:incident_id/postmortem/generate", to: "incidents#generate_postmortem", as: :incident_postmortem_generate
    post "/incidents/:incident_id/postmortem/start_blank", to: "incidents#start_blank_postmortem", as: :incident_postmortem_start_blank
    patch "/incidents/:incident_id/postmortem/status", to: "incidents#update_postmortem_status", as: :incident_postmortem_status
    get "/incidents/:incident_id/postmortem/revisions", to: "incidents#postmortem_revisions", as: :incident_postmortem_revisions
    post "/incidents/:incident_id/postmortem/ai_rewrite", to: "incidents#ai_rewrite_postmortem", as: :incident_postmortem_ai_rewrite
    get "/catalogue", to: "catalogue#index", as: :catalogue
    get "/catalogue/:type_slug", to: "catalogue#show", as: :catalogue_type
    post "/catalogue/types", to: "catalogue#create_type"
    patch "/catalogue/types/:id", to: "catalogue#update_type"
    delete "/catalogue/types/:id", to: "catalogue#destroy_type"
    post "/catalogue/:type_slug/entries", to: "catalogue#create_entry"
    patch "/catalogue/entries/:id", to: "catalogue#update_entry"
    delete "/catalogue/entries/:id", to: "catalogue#destroy_entry"
    get "/catalogue/search/members", to: "catalogue#search_members", as: :catalogue_search_members
    get "/catalogue/search/channels", to: "catalogue#search_channels", as: :catalogue_search_channels

    resources :webhooks, only: [ :create, :update, :destroy ] do
      member do
        post :test
        post :activate
        post :deactivate
        get :signing_secret
      end
      get :sample_payload, on: :collection
      resources :deliveries, only: [], controller: "webhook_deliveries" do
        member do
          post :replay
        end
      end
    end

    get "/settings/members", to: "settings#members", as: :settings_members

    # The gateway and developer screens used to live under /settings.
    get "/settings/permissions", to: redirect("/app/gateway/permissions")
    get "/settings/activity", to: redirect("/app/gateway/activity")
    get "/settings/approvals", to: redirect("/app/gateway/approvals")
    get "/settings/webhooks", to: redirect("/app/developer/webhooks")
    get "/settings/api-keys", to: redirect("/app/developer/api-keys")
  end

  # Targets for `config.exceptions_app`, which is how Rails reaches these once
  # it stops rendering its own debug pages.
  match "/404", to: "errors#not_found", via: :all
  match "/422", to: "errors#unprocessable", via: :all
  match "/500", to: "errors#server_error", via: :all

  # Last route wins nothing above it. Turning an unmatched path into a real
  # action rather than a RoutingError is what gives development the same styled
  # page production gets.
  # Rails-internal paths (Active Storage blobs, direct uploads, representations)
  # are drawn after this file, so an unconstrained catch-all would shadow them.
  match "*path", to: "errors#not_found", via: :all,
        constraints: ->(req) { !req.path.start_with?("/rails/") }
end
