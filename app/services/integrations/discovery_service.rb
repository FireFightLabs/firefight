module Integrations
  # Reconciles integration_tools with what the integration offers - an MCP
  # server's tools/list, or a native pack's code-declared definitions. Same
  # semantics either way: new tools arrive disabled (the admin allowlists),
  # changed schemas update in place, vanished tools are disabled but never
  # deleted (their action rows and grants stay; the config check stops calls).
  class DiscoveryService
    def self.sync!(integration)
      seen = integration.native? ? native_tools(integration) : remote_tools(integration)

      integration.tools.where.not(name: seen).find_each { |tool| tool.update!(enabled: false) }
      seen
    end

    def self.remote_tools(integration)
      environment_row = integration.resolve_environment(nil) || integration.integration_environments.enabled.first
      client = McpClient.new(server_url: integration.server_url,
                             headers: Credentials.headers_for(environment_row))

      client.tools_list.map do |remote|
        name = remote["name"].to_s.downcase.gsub(/[^a-z0-9_.]/, "_")
        tool = integration.tools.find_or_initialize_by(name: name)
        tool.update!(
          description: remote["description"],
          params_schema: remote["inputSchema"] || {},
          read_only: remote.dig("annotations", "readOnlyHint") == true,
          spec: { "tool_name" => remote["name"] }
        )
        name
      end
    end

    def self.native_tools(integration)
      NativePacks.fetch!(integration).class.tool_definitions.map do |definition|
        tool = integration.tools.find_or_initialize_by(name: definition.name)
        tool.update!(
          description: definition.description,
          params_schema: definition.params_schema,
          read_only: definition.read_only,
          spec: {}
        )
        definition.name
      end
    end
  end
end
