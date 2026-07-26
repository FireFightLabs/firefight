module Integrations
  # Runs an authorized tool call against the external MCP server with the
  # resolved environment's credentials. The gateway has already said yes;
  # this only executes.
  class McpExecutor
    def self.call(tool:, environment_row:, arguments:)
      client = McpClient.new(
        server_url: tool.integration.server_url,
        headers: Credentials.headers_for(environment_row)
      )
      client.call_tool(name: tool.remote_name, arguments: arguments)
    end
  end
end
