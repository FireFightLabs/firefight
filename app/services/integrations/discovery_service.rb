module Integrations
  # Vanished tools are marked removed, never deleted or flipped off, so their grants
  # and allowlist survive a return. The config check stops calls meanwhile. A tool seen for the first time arrives
  # switched on, reads and changes alike, unless Halon would call it by another connection's tool's name. A tool seen
  # before keeps whatever an admin chose for it. A tool reads when its server says so or the registry does, unless the
  # registry says it writes, or when an admin marked it as a read on a server Firefight cannot know.
  class DiscoveryService
    # Each minted action joins its permission packs once every tool is saved, and every tool's length is counted from
    # the connection's environments read once.
    def self.sync!(integration)
      Ability::Role.filing_together(integration) { integration.counting_tools_together { discover!(integration) } }
    end

    # The connection's tools are read once, and a new tool is saved switched on in the same write unless another
    # connection's tool shares its name as Halon calls it, read once for every new tool.
    def self.discover!(integration)
      entry = IntegrationProvider.find(integration.provider)
      definitions = integration.executor.tool_definitions(integration)
      known = integration.tools.reload.index_by(&:name)
      namesakes = integration.namesakes_for(definitions.map(&:name) - known.keys)
      seen = definitions.map do |definition|
        tool = known[definition.name] || integration.tools.build(name: definition.name, enabled: !namesakes.key?(definition.name))
        declared = entry ? entry.reads?(definition.name, declared: definition.read_only) : definition.read_only
        tool.assign_attributes(
          description: definition.description,
          params_schema: definition.params_schema,
          read_only: declared || tool.marked_read?,
          spec: definition.spec.to_h.merge(Integration::Tool::DECLARED_READ => declared),
          removed_at: nil
        )
        tool.save!
        definition.name
      end

      integration.tools.available.where.not(name: seen).find_each { |tool| tool.update!(removed_at: Time.current) }
      seen
    end
    private_class_method :discover!
  end
end
