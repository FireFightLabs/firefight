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

    # A pack beside a remote server added tools since the connection last listed its server's, so they are saved with the
    # server's tools as the connection last listed them, without asking the server again.
    def self.add_beside!(integration)
      beside = McpExecutor.beside_tool_definitions(integration)
      return [] if beside.empty?

      listed = integration.tools.available.reject { |tool| beside.any? { |definition| definition.name == tool.name } }.map do |tool|
        ToolDefinition.new(name: tool.name, description: tool.description, params_schema: tool.params_schema, read_only: tool.declared_read?, spec: tool.spec.to_h)
      end
      Integration::Tool.transaction do
        Ability::Role.filing_together(integration) { integration.counting_tools_together { save_all!(integration, listed + beside) } }
      end
    end

    # The connection's tools are read once. A tool seen before is saved on its own, and the new ones together, each
    # switched on unless another connection's tool shares its name as Halon calls it, read once for every new tool.
    def self.save_all!(integration, definitions)
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

      integration.tools.available.where.not(name: seen).find_each { |tool| tool.update!(removed_at: Time.current) }
      seen
    end
    private_class_method :save_all!
  end
end
