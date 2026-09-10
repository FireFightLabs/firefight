module Integrations
  # Vanished tools are marked removed, never deleted or flipped off, so their grants
  # and allowlist survive a return. The config check stops calls meanwhile.
  class DiscoveryService
    def self.sync!(integration)
      seen = integration.executor.tool_definitions(integration).map do |definition|
        tool = integration.tools.find_or_initialize_by(name: definition.name)
        tool.update!(
          description: definition.description,
          params_schema: definition.params_schema,
          read_only: definition.read_only,
          spec: definition.spec,
          removed_at: nil
        )
        definition.name
      end

      integration.tools.available.where.not(name: seen).find_each { |tool| tool.update!(removed_at: Time.current) }
      seen
    end
  end
end
