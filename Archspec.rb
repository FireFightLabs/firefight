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

# Covers every folder under app/services except handlers, dispatchers and the integrations layer, so new folders are checked too.
handler_and_layer_files = Dir.chdir(__dir__) do
  Dir.glob("app/services/{commands,interactions,events,integrations}/**/*.rb")
end.sort

plain_services = Dir.chdir(__dir__) { Dir.glob("app/services/**/*.rb") }.sort -
                 DISPATCHER_FILES - SLACK_AUTH_FILES - handler_and_layer_files

api_controller_files = Dir.chdir(__dir__) { Dir.glob("app/controllers/api/**/*.rb") }.sort -
                       SLACK_ENTRY_FILES

# The operator console is its own set of components, so it can be removed or replaced without changing app code.
operator_controller_files = Dir.chdir(__dir__) { Dir.glob("app/controllers/operator/**/*.rb") }.sort
operator_model_files = Dir.chdir(__dir__) { Dir.glob("app/models/operator/**/*.rb") }.sort
operator_serializer_files = Dir.chdir(__dir__) { Dir.glob("app/serializers/operator/**/*.rb") }.sort

controller_files = Dir.chdir(__dir__) { Dir.glob("app/controllers/**/*.rb") }.sort -
                   SLACK_ENTRY_FILES - api_controller_files - operator_controller_files

component :controllers, in: controller_files
component :api_controllers, in: api_controller_files
component :slack_entry_controllers, in: SLACK_ENTRY_FILES
component :dispatchers, in: DISPATCHER_FILES
component :slack_auth, in: SLACK_AUTH_FILES
component :handlers, in: "app/services/{commands,interactions,events}/**/*.rb"
component :services, in: plain_services
component :serializers, in: Dir.chdir(__dir__) { Dir.glob("app/serializers/**/*.rb") }.sort - operator_serializer_files

# The only file allowed to use Flipper.
FEATURE_FLAG_FILES = %w[app/models/feature_flags.rb].freeze

model_files = Dir.chdir(__dir__) { Dir.glob("app/models/**/*.rb") }.sort - FEATURE_FLAG_FILES - operator_model_files

component :models, in: model_files
component :feature_flags, in: FEATURE_FLAG_FILES

component :operator_controllers, in: operator_controller_files
component :operator_models, in: operator_model_files
component :operator_serializers, in: operator_serializer_files

# The one file outside a platform directory allowed to name platform adapters.
PLATFORM_FACTORY_FILES = %w[app/adapters/workspace_adapter.rb].freeze

plain_adapters = Dir.chdir(__dir__) { Dir.glob("app/adapters/*.rb") }.sort - PLATFORM_FACTORY_FILES

component :platform_factory, in: PLATFORM_FACTORY_FILES
component :adapters, in: plain_adapters + %w[app/adapters/alert_providers/**/*.rb]
component :slack_adapter, in: "app/adapters/slack/**/*.rb"
component :integrations_layer,
          in: %w[app/adapters/integrations/**/*.rb app/services/integrations/**/*.rb]
component :channels, in: "app/channels/**/*.rb"
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
# Every client under app/adapters/integrations, the shared ones and each provider's own, found by file so a provider's
# client needs no line here.
INTEGRATION_CLIENT_CONSTANTS = Dir.chdir(__dir__) { Dir.glob("app/adapters/integrations/*.rb") }.sort.map do |path|
  "Integrations::#{File.basename(path, '.rb').split('_').map(&:capitalize).join}"
end - %w[Integrations::Sandboxes Integrations::WebSearch]
component :integration_clients, constants: INTEGRATION_CLIENT_CONSTANTS

# A provider's own code: its pack, capabilities adapter, map reader, baseline reader, health probe, link builder, read
# guard, error reader, issue tracker, map event source and definition. Found by file, so a new provider needs no line here. The shared contracts beside them
# (Capabilities::Adapter, Capabilities::Answers, the run history every adapter reads into, Capabilities::History, and the
# helper the providers that attach runs to an answer share, Capabilities::RunHistory) are not a provider's.
SHARED_PROVIDER_CONTRACTS = %w[
  app/services/integrations/capabilities/adapter.rb app/services/integrations/capabilities/answers.rb
  app/services/integrations/capabilities/history.rb app/services/integrations/capabilities/run_history.rb
].freeze
PROVIDER_CODE_NAMESPACES = Dir.chdir(__dir__) do
  Dir.glob("app/services/integrations/{packs,capabilities,map_readers,baseline_readers,health_probes,source_links,read_guards,error_readers,issue_trackers,map_event_sources,providers}/*.rb")
end.sort.-(SHARED_PROVIDER_CONTRACTS).map do |path|
  path.delete_prefix("app/services/").delete_suffix(".rb").split("/").map { |part| part.split("_").map(&:capitalize).join }.join("::")
end
component :provider_code, namespace: PROVIDER_CODE_NAMESPACES
component :sandbox_clients, namespace: "Integrations::Sandboxes"
component :operator_namespace, namespace: "Operator"

# Handlers naming Slack::Modals and the like are grandfathered debt, not precedent.
slack_namespace.can_only_be_used_by :slack_adapter, :slack_client, :slack_entry_controllers, :slack_auth, :platform_factory

slack_client.can_only_be_used_by :slack_adapter, :slack_namespace

# Handlers are reached through dispatch only, HomeHandler sub-routes to leaf commands.
handlers.can_only_be_used_by :dispatchers, :handlers

handlers.cannot_use :controllers, :api_controllers, :serializers
workflows.cannot_use :controllers, :handlers, :dispatchers, :serializers, :adapters
serializers.cannot_use :adapters, :handlers, :dispatchers, :jobs
jobs.cannot_use :controllers, :api_controllers, :serializers

channels.cannot_use :controllers, :api_controllers, :handlers, :dispatchers, :adapters, :slack_adapter,
                    :serializers, :jobs, :mcp

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
ability_gateway.can_only_be_used_by :dispatchers, :mcp, :controllers, :api_controllers, :models, :operator_models,
                                    :operator_namespace

# Written by the gateway, read by the governance pages and the operator console.
ability_ledger.can_only_be_used_by :ability_gateway, :models, :controllers, :serializers, :operator_models, :operator_namespace

solid_workflow_engine.cannot_use :models, :services, :controllers, :api_controllers, :adapters,
                                 :slack_adapter, :handlers, :dispatchers, :jobs, :workflows,
                                 :serializers, :mcp, :events_pipeline, :firefight_ai_engine

# The operator console reads and controls every workflow run, so it reads the engine's tables directly, as Flightdeck
# reads Solid Queue's.
solid_workflow_namespace.can_only_be_used_by :workflows, :solid_workflow_engine, :operator_models, :operator_controllers,
                                             :operator_namespace

# Delivery, jobs and platform calls live in the app, the engine only reads models and returns results.
firefight_ai_engine.can_only_use :models, :firefight_ai_engine

# The engine reasons and returns, the app writes the record. A chat reaches it as a RubyLLM::Chat.
firefight_ai_engine.cannot_reference_constants "Investigation", "Chat"

# App code must not reference the operator console. The console depends on the app and never the other way, so a new
# console replaces only these files.
operator_namespace.can_only_be_used_by :operator_controllers, :operator_models, :operator_serializers

# The operator's controllers, models and serializers follow the same layer rules as the app's.
operator_controllers.cannot_call :record_change!
operator_models.cannot_use :controllers, :api_controllers, :dispatchers, :handlers, :serializers, :adapters, :services,
                           :operator_controllers, :operator_serializers
operator_models.cannot_call :render, :redirect_to, :params, :session, :cookies, :flash, receiver: :none
operator_serializers.cannot_use :adapters, :handlers, :dispatchers, :jobs, :operator_controllers
operator_controllers.cannot_use :handlers, :dispatchers, :adapters, :slack_adapter, :mcp
(component_specs.keys - [ :operator_controllers, :operator_models, :operator_serializers, :operator_namespace ]).each do |component_name|
  send(component_name).cannot_use :operator_controllers, :operator_models, :operator_serializers
end

# Provider clients and credential shapes stay behind the integrations layer.
integration_clients.can_only_be_used_by :integrations_layer, :sandbox_clients, :provider_code

# A box is started, reached and stopped only through Integrations::CodeReading, so a new provider changes one class.
sandbox_clients.can_only_be_used_by :integrations_layer, :provider_code

# Nothing outside the integrations layer names a provider's code. The rest of the app reaches a provider only through
# the shared contracts (Integrations::Capabilities, Credentials, SourceLinks, ConnectionSettings, the executors), so a
# provider's code can change without touching anything else.
provider_code.can_only_be_used_by :integrations_layer

# A provider's API client is used only by that provider's own files, the ones named for it (packs/northflank.rb,
# packs/northflank/, capabilities/northflank.rb), so how one provider reaches its API is never another one's concern.
# The shared clients (MCP, OAuth, HTTP, the public address check and git's smart HTTP for any code host) are every
# provider's, and a client may build on another, such as several coding agents' clients on one base.
class ProviderClientsStayHome
  SHARED = %w[Integrations::McpClient Integrations::OauthClient Integrations::Http Integrations::PublicAddress Integrations::GitHttp].freeze

  def initialize(clients)
    @owners = (clients - SHARED).to_h { |client| [ client, client.delete_prefix("Integrations::").sub(/(Api|App)\z/, "").gsub(/(?<!\A)([A-Z])/, '_\1').downcase ] }
  end

  def id = "integrations.provider_client"

  def evaluate(graph)
    graph.dependency_edges.filter_map do |edge|
      target = graph.resolve_edge_constant(edge)
      owner = @owners.find { |client, _owner| target == client || target.start_with?("#{client}::") }&.last
      path = graph.files[edge.from_path]&.relative_path || edge.from_path.to_s
      next if owner.nil? || own?(path, owner) || path.start_with?("app/adapters/integrations/")

      ArchSpec::Diagnostic.new(rule: id, message: "#{target} is #{owner}'s API client, so only #{owner}'s own files may use it",
                               location: edge.location, evidence: "#{graph.edge_source_name(edge)} #{edge.verb} #{edge.to}")
    end
  end

  private

  def own?(path, owner) = path.match?(%r{\Aapp/(services|adapters)/integrations/(.+/)?#{owner}(_api|_app)?(\.rb\z|/)})
end
rule ProviderClientsStayHome.new(INTEGRATION_CLIENT_CONSTANTS)

# A RubyLLM context copies the deployment's configuration, Firefight's own keys included, so one built anywhere else
# could send a workspace's call on Firefight's key or the reverse. Only WorkspaceAiAccount#llm_context builds one, from
# a configuration with every provider setting emptied, and the engine runs what it is handed. Only AiProviders reads
# RubyLLM::Provider, so what a provider needs is decided in one place.
class AiKeysStayWithTheirAccount
  CONTEXT_BUILDERS = %w[app/models/workspace_ai_account.rb].freeze
  PROVIDER_READERS = %w[app/models/ai_providers.rb].freeze
  ENGINE = "engines/firefight_ai/".freeze
  CONTEXT_CALL = /RubyLLM\s*\.\s*context\b|RubyLLM::Context\s*\.\s*new\b/

  def initialize(root) = @root = root

  def id = "ai.keys"

  def evaluate(graph)
    contexts = graph.edges.filter_map do |edge|
      next unless edge.type == :calls_named_method && %w[context new].include?(edge.to.to_s)

      path = relative(graph, edge)
      next if CONTEXT_BUILDERS.include?(path) || path.start_with?(ENGINE)
      next unless line(edge).match?(CONTEXT_CALL)

      ArchSpec::Diagnostic.new(rule: id, message: "Only WorkspaceAiAccount#llm_context builds a RubyLLM context, from an emptied configuration",
                               location: edge.location, evidence: "#{graph.edge_source_name(edge)} builds a RubyLLM context")
    end
    contexts + provider_reads(graph)
  end

  private

  def provider_reads(graph)
    graph.dependency_edges.filter_map do |edge|
      target = graph.resolve_edge_constant(edge).to_s
      next unless target == "RubyLLM::Provider" || edge.to.to_s.sub(/\A::/, "") == "RubyLLM::Provider"

      path = relative(graph, edge)
      next if PROVIDER_READERS.include?(path) || path.start_with?(ENGINE)

      ArchSpec::Diagnostic.new(rule: id, message: "Only AiProviders reads RubyLLM::Provider", location: edge.location,
                               evidence: "#{graph.edge_source_name(edge)} references RubyLLM::Provider")
    end
  end

  def relative(graph, edge) = graph.files[edge.from_path]&.relative_path || edge.from_path.to_s

  def line(edge)
    path = edge.location&.path.to_s
    path = File.join(@root, path) unless path.start_with?("/")
    File.readlines(path)[edge.location.line - 1].to_s
  rescue SystemCallError, NoMethodError
    ""
  end
end
rule AiKeysStayWithTheirAccount.new(__dir__)

feature_flags.can_only_use :models

# Keep last, the Flipper ban only covers components declared above.
(component_specs.keys - [ :feature_flags ]).each do |component_name|
  send(component_name).cannot_reference_constants "Flipper"
end
