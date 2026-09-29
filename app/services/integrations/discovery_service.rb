module Integrations
  # Vanished tools are marked removed, never deleted or flipped off, so their grants
  # and allowlist survive a return. The config check stops calls meanwhile.
  class DiscoveryService
    def self.sync!(integration)
      reading = IntegrationProvider.find(integration.provider)&.read_only_tools || []
      seen = integration.executor.tool_definitions(integration).map do |definition|
        tool = integration.tools.find_or_initialize_by(name: definition.name)
        tool.update!(
          description: definition.description,
          params_schema: definition.params_schema,
          read_only: definition.read_only || reading.include?(definition.name),
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
