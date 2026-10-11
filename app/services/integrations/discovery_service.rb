module Integrations
  # Vanished tools are marked removed, never deleted or flipped off, so their grants
  # and allowlist survive a return. The config check stops calls meanwhile. A tool seen for the first time arrives
  # switched on, reads and changes alike, unless Halon would call it by another connection's tool's name. A tool seen
  # before keeps whatever an admin chose for it. A tool reads when its server says so or the registry does, unless the
  # registry says it writes, or when an admin marked it as a read on a server Firefight cannot know.
  class DiscoveryService
    # Each minted action joins its permission packs once every tool is saved.
    def self.sync!(integration)
      Ability::Role.filing_together(integration) { discover!(integration) }
    end

    def self.discover!(integration)
      entry = IntegrationProvider.find(integration.provider)
      arrived = []
      seen = integration.executor.tool_definitions(integration).map do |definition|
        tool = integration.tools.find_or_initialize_by(name: definition.name)
        declared = entry ? entry.reads?(definition.name, declared: definition.read_only) : definition.read_only
        tool.assign_attributes(
          description: definition.description,
          params_schema: definition.params_schema,
          read_only: declared || tool.marked_read?,
          spec: definition.spec.to_h.merge(Integration::Tool::DECLARED_READ => declared),
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
    private_class_method :discover!, :switch_on
  end
end
