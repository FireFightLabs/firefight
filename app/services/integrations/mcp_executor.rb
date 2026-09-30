module Integrations
  # The gateway has already said yes before call is reached. This only executes.
  class McpExecutor
    # A remote server keeps its own state, so the run's box key means nothing to it.
    def self.call(tool:, environment_row:, arguments:, box_key: nil)
      result = client_for(tool.integration, environment_row)
               .call_tool(name: tool.remote_name, arguments: arguments)
      SourceLinks.attach(ToolResult.normalize(result), integration: tool.integration, tool_name: tool.name, arguments: arguments)
    end

    # Names are sanitized into action-key-safe form, spec keeps the server's own name for the call.
    def self.tool_definitions(integration)
      environment_row = integration.resolve_environment(nil) || integration.integration_environments.enabled.first

      client_for(integration, environment_row).tools_list.map do |remote|
        ToolDefinition.new(
          name: remote["name"].to_s.downcase.gsub(/[^a-z0-9_.]/, "_"),
          description: remote["description"],
          params_schema: remote["inputSchema"] || {},
          read_only: remote.dig("annotations", "readOnlyHint") == true,
          spec: { "tool_name" => remote["name"] }
        )
      end
    end

    def self.check_health!(environment_row)
      client_for(environment_row.integration, environment_row).ping
    end

    # A remote server lists tools, not what it reaches, so a provider goes on the map through a reader written for it,
    # which calls only the tools an admin switched on. Without a reader the connection puts nothing on the map.
    MAP_READERS = { MapReaders::Planetscale::PROVIDER => MapReaders::Planetscale, MapReaders::Cloudflare::PROVIDER => MapReaders::Cloudflare }.freeze
    # How often a reader is swept on the hourly schedule, when it says. Sync now reads it at once whatever this says.
    DEFAULT_MAP_EVERY = 1.hour

    def self.map_every(integration)
      reader = MAP_READERS[integration.provider]
      reader&.const_defined?(:EVERY, false) ? reader::EVERY : DEFAULT_MAP_EVERY
    end

    def self.map_of(environment_row)
      integration = environment_row.integration
      reader = MAP_READERS[integration.provider]
      return unless reader

      client = client_for(integration, environment_row)
      tools = integration.tools.enabled.available.index_by(&:name)
      reader.new do |name, arguments, reads = nil|
        tool = tools[name]
        tool&.swept!(arguments, reads) { client.call_tool(name: tool.remote_name, arguments: arguments) }
      end.map
    end


    # No remote provider reads baselines yet, so its resources have none.
    def self.baselines_of(_environment_row, _resources, _window) = nil

    def self.client_for(integration, environment_row)
      McpClient.new(server_url: integration.server_url, headers: Credentials.headers_for(environment_row))
    end
    private_class_method :client_for
  end
end
