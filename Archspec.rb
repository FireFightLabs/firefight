# Architecture rules, checked by `bundle exec archspec check` (part of bin/ci).
# archspec_todo.yml grandfathers the violations that predate the rules, and
# each refactor shrinks that list. New violations fail the build.
#
# The rules encode the boundaries documented in CLAUDE.md and
# docs/architecture.md: platform code stays inside adapters, entry points stay
# thin and never share code sideways, models own domain logic without reaching
# into services, and the engines stay generic.
#
# File components stay disjoint, each file belongs to exactly one, because
# consumer allowlists check every component a referencing file belongs to.
# Dir.glob computes the lists below, so new files land in the right component
# without editing this file.

todo "archspec_todo.yml"

ignore "engines/*/test/**/*.rb"

# --- Components -------------------------------------------------------------

DISPATCHER_FILES = %w[
  app/services/command_dispatcher.rb
  app/services/interaction_dispatcher.rb
  app/services/event_dispatcher.rb
  app/services/authorized_dispatch.rb
  app/services/handler_authorization.rb
].freeze

# The Slack webhook entry points: they verify signatures and normalize raw
# payloads through the parsers, so they are allowed to know Slack exists.
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
component :models, in: "app/models/**/*.rb"
component :serializers, in: "app/serializers/**/*.rb"

# The factory is the port-selection point, the one file outside a platform
# directory allowed to name platform adapters.
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

# Namespace and constant components, for boundaries that are names rather
# than folders.
component :slack_namespace, namespace: "Slack"
component :slack_client, constants: %w[Slack::Client]
component :solid_workflow_namespace, namespace: "SolidWorkflow"
component :ability_gateway, constants: %w[AbilityGateway]
component :ability_ledger, constants: %w[Ability::Invocation]
component :integration_clients,
          constants: %w[Integrations::McpClient Integrations::OauthClient Integrations::GithubApp
                        Integrations::CloneManager Integrations::Http]

# --- Platform containment (what a Teams adapter depends on) ------------------

# Slack-specific code lives in app/adapters/slack. The only outside consumers
# are the Slack webhook controllers and the OAuth install flow. Handlers
# naming Slack::Modals, the Interaction model parsing Slack::PrivateMetadata,
# and friends are grandfathered debt, not precedent.
slack_namespace.can_only_be_used_by :slack_adapter, :slack_entry_controllers, :slack_auth, :platform_factory

# The raw API client never leaves Slack adapter code, not even for the entry
# controllers or the factory.
slack_client.can_only_be_used_by :slack_adapter, :slack_namespace

# --- Layer hierarchy (thin entry points) ------------------------------------

# Controller -> Dispatcher -> Handler -> Service. Handlers are reached through
# dispatch (HomeHandler sub-routes to leaf commands), never called sideways
# from controllers, MCP, jobs, or services.
handlers.can_only_be_used_by :dispatchers, :handlers

handlers.cannot_use :controllers, :api_controllers, :serializers
workflows.cannot_use :controllers, :handlers, :dispatchers, :serializers, :adapters
serializers.cannot_use :adapters, :handlers, :dispatchers, :jobs
jobs.cannot_use :controllers, :api_controllers, :serializers

# Controller vocabulary stays in controllers.
models.cannot_call :render, :redirect_to, :params, :session, :cookies, :flash, receiver: :none
services.cannot_call :render, :redirect_to, :session, :cookies, :flash, receiver: :none

# --- Thick models, services for coordination only ---------------------------

# Models own their domain logic and never reach up. Commit hooks enqueueing
# jobs are the documented event-bus pattern, so jobs stay allowed.
models.cannot_use :controllers, :api_controllers, :dispatchers, :handlers, :serializers, :adapters
models.cannot_use :services

# --- Four entry points, one write path --------------------------------------

# Slack, API, MCP, and the dashboard all normalize input and call shared
# services. They never reference each other, so shared behavior has nowhere
# to live but a service or a model.
mcp.cannot_use :controllers, :api_controllers, :handlers, :dispatchers, :serializers
api_controllers.cannot_use :mcp, :handlers

# Snapshots are written by models and services, never inline at an entry
# point. The postmortem paths in incidents_controller are grandfathered.
controllers.cannot_call :record_change!
api_controllers.cannot_call :record_change!
mcp.cannot_call :record_change!

# --- Governance -------------------------------------------------------------

# One authorization chokepoint: the dispatchers, the API auth concern, and
# MCP. No inline permission checks growing in models, services, or jobs.
ability_gateway.can_only_be_used_by :dispatchers, :mcp, :controllers, :api_controllers, :models

# The invocation ledger is written by the gateway (a model) and read by the
# governance pages. Nothing else touches it.
ability_ledger.can_only_be_used_by :ability_gateway, :models, :controllers, :serializers

# --- Engines ----------------------------------------------------------------

# SolidWorkflow knows nothing about the app. Zero references, locked.
solid_workflow_engine.cannot_use :models, :services, :controllers, :api_controllers, :adapters,
                                 :slack_adapter, :handlers, :dispatchers, :jobs, :workflows,
                                 :serializers, :mcp, :events_pipeline, :firefight_ai_engine

# The app touches the engine only where workflows are defined.
solid_workflow_namespace.can_only_be_used_by :workflows, :solid_workflow_engine

# The AI engine reads models and enqueues jobs. Everything else it does today
# goes through runtime adapter calls that static analysis cannot see, but the
# constants it references stay frozen at models plus jobs.
firefight_ai_engine.can_only_use :models, :jobs, :firefight_ai_engine

# --- Integrations isolation -------------------------------------------------

# Provider clients and credential shapes stay behind the integrations layer,
# so a provider swap never touches an entry point.
integration_clients.can_only_be_used_by :integrations_layer
