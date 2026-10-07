module Integrations
  # Vanished tools are marked removed, never deleted or flipped off, so their grants
  # and allowlist survive a return. The config check stops calls meanwhile. A tool seen for the first time arrives
  # switched on, reads and changes alike, unless Halon would call it by another connection's tool's name. A tool seen
  # before keeps whatever an admin chose for it.
  class DiscoveryService
    def self.sync!(integration)
      reading = IntegrationProvider.find(integration.provider)&.read_only_tools || []
      arrived = []
      seen = integration.executor.tool_definitions(integration).map do |definition|
        tool = integration.tools.find_or_initialize_by(name: definition.name)
        tool.assign_attributes(
          description: definition.description,
          params_schema: definition.params_schema,
          read_only: definition.read_only || reading.include?(definition.name),
          spec: definition.spec,
          removed_at: nil
        )
        arrived << tool if tool.new_record?
        tool.save!
        definition.name
      end

      integration.tools.available.where.not(name: seen).find_each { |tool| tool.update!(removed_at: Time.current) }
      switch_on(integration, arrived)
      seen
    end

    # Read once every new tool is saved, so tools arriving together are checked against each other's connections too.
    def self.switch_on(integration, arrived)
      return if arrived.empty?

      namesakes = Integration.find(integration.id).tool_namesakes
      arrived.each { |tool| tool.update!(enabled: true) unless namesakes.key?(tool.name) }
    end
    private_class_method :switch_on
  end
end
