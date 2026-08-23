module Integrations
  # Reconciles integration_tools with what the executor's discovery returns.
  # Same semantics for every kind, new tools arrive disabled (the admin
  # allowlists), changed schemas update in place, vanished tools are disabled
  # but never deleted (their action rows and grants stay, the config check
  # stops calls).
  class DiscoveryService
    def self.sync!(integration)
      seen = integration.executor.tool_definitions(integration).map do |definition|
        tool = integration.tools.find_or_initialize_by(name: definition.name)
        tool.update!(
          description: definition.description,
          params_schema: definition.params_schema,
          read_only: definition.read_only,
          spec: definition.spec
        )
        definition.name
      end

      integration.tools.where.not(name: seen).find_each { |tool| tool.update!(enabled: false) }
      seen
    end
  end
end
