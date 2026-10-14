# A connection with as many switched on tools as a test needs, and a count of the queries a block makes, answers from
# the query cache included since each still builds its rows, so a test can prove the work a page or a connect does stays
# the same however many tools a workspace has.
module ManyToolsHelper
  def connection_with_tools(workspace, count, name: "Big")
    integration = workspace.integrations.create!(kind: Integration::KIND_MCP, provider: Integration::PROVIDER_CUSTOM_MCP, name: name,
                                                 settings: { "server_url" => "https://mcp.example.com/mcp" })
    integration.integration_environments.create!(credentials: { authorization: "Bearer x" }.to_json)
    count.times do |index|
      integration.tools.create!(name: "tool_#{index}", description: "Does thing #{index}", read_only: index.even?, enabled: true,
                                params_schema: { "type" => "object", "properties" => { "service" => { "type" => "string" } } })
    end
    integration
  end

  def queries_made
    count = 0
    counter = ->(*, payload) { count += 1 unless %w[SCHEMA TRANSACTION].include?(payload[:name]) }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { yield }
    count
  end
end
