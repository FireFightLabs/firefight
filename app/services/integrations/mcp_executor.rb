module Integrations
  # Everything kind: mcp knows about talking to its provider: executing an
  # authorized call, listing what the server offers, probing health. The
  # gateway has already said yes before call is reached. This only executes.
  class McpExecutor
    def self.call(tool:, environment_row:, arguments:)
      result = client_for(tool.integration, environment_row)
               .call_tool(name: tool.remote_name, arguments: arguments)
      ToolResult.normalize(result)
    end

    # tools/list, normalized. Names are sanitized into action-key-safe form.
    # Spec keeps the server's own name for the call.
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

    def self.client_for(integration, environment_row)
      McpClient.new(server_url: integration.server_url, headers: Credentials.headers_for(environment_row))
    end
    private_class_method :client_for
  end
end
