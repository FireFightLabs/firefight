module Integrations
  # Vanished tools are marked removed, never deleted or flipped off, so their grants
  # and allowlist survive a return. The config check stops calls meanwhile. A tool seen for the first time arrives
  # switched on, reads and changes alike, unless Halon would call it by another connection's tool's name. A tool seen
  # before keeps whatever an admin chose for it. A tool reads when its server says so or the registry does, unless the
  # registry says it writes, or when an admin marked it as a read on a server Firefight cannot know.
  class DiscoveryService
    # The server is asked first. Saving its tools and filing their actions in their packs is then one transaction, so a
    # failure part way, filing included, leaves nothing half saved and the writes commit once. Each minted action joins
    # its packs once every tool is saved, and every tool's length is counted from the environments read once.
    def self.sync!(integration)
      definitions = integration.executor.tool_definitions(integration)
      Integration::Tool.transaction do
        Ability::Role.filing_together(integration) { integration.counting_tools_together { save_all!(integration, definitions) } }
      end
    end

    # The tools Firefight adds to a remote connection beside its server's (Provider#firefight_tools), saved without asking
    # the server, every tool the server listed left as it is, and one of Firefight's no longer offered taken as gone. A
    # data migration gives connections made before a tool was added the new one this way, switched on as a discovered
    # tool is. Answers the names saved.
    def self.add_firefight_tools!(integration)
      definitions = McpExecutor.firefight_tool_definitions(integration)
      offered = definitions.map(&:name)
      # One of Firefight's own saved before and no longer offered is taken as gone, never a tool the server listed.
      dropped = integration.tools.available.select { |tool| tool.spec.to_h[Provider::FIREFIGHT_TOOL] == true && !offered.include?(tool.name) }
      return [] if definitions.empty? && dropped.empty?

      Integration::Tool.transaction do
        dropped.each { |tool| tool.update!(removed_at: Time.current) }
        Ability::Role.filing_together(integration) { integration.counting_tools_together { save_all!(integration, definitions, remove: false) } }
      end
    end

    # The connection's tools are read once. A tool seen before is saved on its own, and the new ones together, each
    # switched on unless another connection's tool shares its name as Halon calls it, read once for every new tool.
    def self.save_all!(integration, definitions, remove: true)
      entry = IntegrationProvider.find(integration.provider)
      known = integration.tools.reload.index_by(&:name)
      namesakes = integration.namesakes_for(definitions.map(&:name) - known.keys)
      fresh = definitions.map do |definition|
        tool = known[definition.name] || Integration::Tool.new(integration: integration, name: definition.name, enabled: !namesakes.key?(definition.name))
        declared = entry ? entry.reads?(definition.name, declared: definition.read_only) : definition.read_only
        tool.assign_attributes(
          description: definition.description,
          params_schema: definition.params_schema,
          read_only: declared || tool.marked_read?,
          spec: definition.spec.to_h.merge(Integration::Tool::DECLARED_READ => declared),
          removed_at: nil
        )
        next tool if tool.new_record?

        tool.save!
        nil
      end
      Integration::Tool.insert_discovered!(integration, fresh.compact)
      seen = definitions.map(&:name)
      return seen unless remove

      integration.tools.available.where.not(name: seen).find_each { |tool| tool.update!(removed_at: Time.current) }
      seen
    end
    private_class_method :save_all!
  end
end
