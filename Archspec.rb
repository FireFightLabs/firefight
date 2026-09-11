# archspec_todo.yml stays empty, a new violation means the code is in the wrong place.
# Each file belongs to exactly one component because consumer allowlists check every component
# a referencing file belongs to. Dir.glob builds the lists, so new files need no edit here.

todo "archspec_todo.yml"

ignore "engines/*/test/**/*.rb"

DISPATCHER_FILES = %w[
  app/services/command_dispatcher.rb
  app/services/interaction_dispatcher.rb
  app/services/event_dispatcher.rb
  app/services/authorized_dispatch.rb
  app/services/handler_authorization.rb
].freeze

# The webhook entry points verify signatures and normalize raw payloads, so they may know Slack exists.
SLACK_ENTRY_FILES = %w[
  app/controllers/api/v1/base_controller.rb
  app/controllers/api/v1/commands_controller.rb
  app/controllers/api/v1/interactions_controller.rb
  app/controllers/api/v1/events_controller.rb
].freeze

SLACK_AUTH_FILES = %w[app/services/slack_authentication_service.rb].freeze

plain_services = Dir.chdir(__dir__) { Dir.glob("app/services/*.rb") }.sort -
                 DISPATCHER_FILES - SLACK_AUTH_FILES

api_controller_files = Dir.chdir(__dir__) { Dir.glob("app/controllers/api/**/*.rb") }.sort -
                       SLACK_ENTRY_FILES

controller_files = Dir.chdir(__dir__) { Dir.glob("app/controllers/**/*.rb") }.sort -
                   SLACK_ENTRY_FILES - api_controller_files

component :controllers, in: controller_files
component :api_controllers, in: api_controller_files
component :slack_entry_controllers, in: SLACK_ENTRY_FILES
component :dispatchers, in: DISPATCHER_FILES
component :slack_auth, in: SLACK_AUTH_FILES
component :handlers, in: "app/services/{commands,interactions,events}/**/*.rb"
component :services, in: plain_services + %w[app/services/webhooks/**/*.rb app/services/catalogue/**/*.rb]
component :serializers, in: "app/serializers/**/*.rb"

# The one file allowed to name Flipper, so every flag check goes through a declared constant.
FEATURE_FLAG_FILES = %w[app/models/feature_flags.rb].freeze

model_files = Dir.chdir(__dir__) { Dir.glob("app/models/**/*.rb") }.sort - FEATURE_FLAG_FILES

component :models, in: model_files
component :feature_flags, in: FEATURE_FLAG_FILES

# The one file outside a platform directory allowed to name platform adapters.
PLATFORM_FACTORY_FILES = %w[app/adapters/workspace_adapter.rb].freeze

plain_adapters = Dir.chdir(__dir__) { Dir.glob("app/adapters/*.rb") }.sort - PLATFORM_FACTORY_FILES

component :platform_factory, in: PLATFORM_FACTORY_FILES
component :adapters, in: plain_adapters + %w[app/adapters/alert_providers/**/*.rb]
component :slack_adapter, in: "app/adapters/slack/**/*.rb"
component :integrations_layer,
          in: %w[app/adapters/integrations/**/*.rb app/services/integrations/**/*.rb]
component :jobs, in: "app/jobs/**/*.rb"
component :workflows, in: "app/workflows/**/*.rb"
component :mcp, in: "app/mcp/**/*.rb"
component :events_pipeline, in: "app/events/**/*.rb"
component :solid_workflow_engine, in: "engines/solid_workflow/**/*.rb"
component :firefight_ai_engine, in: "engines/firefight_ai/**/*.rb"

component :slack_namespace, namespace: "Slack"
component :slack_client, constants: %w[Slack::Client]
component :solid_workflow_namespace, namespace: "SolidWorkflow"
component :ability_gateway, constants: %w[AbilityGateway]
component :ability_ledger, constants: %w[Ability::Invocation]
component :integration_clients,
          constants: %w[Integrations::McpClient Integrations::OauthClient Integrations::GithubApp
                        Integrations::CloneManager Integrations::Http]

# Handlers naming Slack::Modals and the like are grandfathered debt, not precedent.
slack_namespace.can_only_be_used_by :slack_adapter, :slack_entry_controllers, :slack_auth, :platform_factory

slack_client.can_only_be_used_by :slack_adapter, :slack_namespace

# Handlers are reached through dispatch only, HomeHandler sub-routes to leaf commands.
handlers.can_only_be_used_by :dispatchers, :handlers

handlers.cannot_use :controllers, :api_controllers, :serializers
workflows.cannot_use :controllers, :handlers, :dispatchers, :serializers, :adapters
serializers.cannot_use :adapters, :handlers, :dispatchers, :jobs
jobs.cannot_use :controllers, :api_controllers, :serializers

# Controller vocabulary stays in controllers.
models.cannot_call :render, :redirect_to, :params, :session, :cookies, :flash, receiver: :none
services.cannot_call :render, :redirect_to, :session, :cookies, :flash, receiver: :none

# Commit hooks enqueueing jobs are the event-bus pattern, so jobs stay allowed.
models.cannot_use :controllers, :api_controllers, :dispatchers, :handlers, :serializers, :adapters
models.cannot_use :services

# Entry points never reference each other, so shared behaviour has nowhere to live but a service or model.
mcp.cannot_use :controllers, :api_controllers, :handlers, :dispatchers, :serializers
api_controllers.cannot_use :mcp, :handlers

# The postmortem paths in incidents_controller are grandfathered.
controllers.cannot_call :record_change!
api_controllers.cannot_call :record_change!
mcp.cannot_call :record_change!

# One authorization chokepoint, no inline permission checks in models, services or jobs.
ability_gateway.can_only_be_used_by :dispatchers, :mcp, :controllers, :api_controllers, :models

# Written by the gateway, read by the governance pages.
ability_ledger.can_only_be_used_by :ability_gateway, :models, :controllers, :serializers

solid_workflow_engine.cannot_use :models, :services, :controllers, :api_controllers, :adapters,
                                 :slack_adapter, :handlers, :dispatchers, :jobs, :workflows,
                                 :serializers, :mcp, :events_pipeline, :firefight_ai_engine

solid_workflow_namespace.can_only_be_used_by :workflows, :solid_workflow_engine

# Delivery, jobs and platform calls live in the app, the engine only reads models and returns results.
firefight_ai_engine.can_only_use :models, :firefight_ai_engine

# Provider clients and credential shapes stay behind the integrations layer.
integration_clients.can_only_be_used_by :integrations_layer

# FeatureFlags sits outside models only to hold Flipper, so it may reach models and nothing else.
feature_flags.can_only_use :models

# Unreleased work is checked through FeatureFlags, never Flipper directly. Flipper is a gem constant,
# so the ban goes on every other component. Keep this last so it covers every component above.
(component_specs.keys - [ :feature_flags ]).each do |component_name|
  send(component_name).cannot_reference_constants "Flipper"
end
