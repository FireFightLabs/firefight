module Integrations
  # Pulls the external server's tools/list and reconciles integration_tools:
  # new tools arrive disabled (the admin allowlists), changed schemas update
  # in place, vanished tools are disabled but never deleted (their action
  # rows and grants stay; the config check stops calls).
  class DiscoveryService
    def self.sync!(integration)
      environment_row = integration.resolve_environment(nil) || integration.integration_environments.enabled.first
      client = McpClient.new(server_url: integration.server_url,
                             headers: Credentials.headers_for(environment_row))

      seen = client.tools_list.map do |remote|
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

      integration.tools.where.not(name: seen).find_each { |tool| tool.update!(enabled: false) }
      seen
    end
  end
end
