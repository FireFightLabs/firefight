require "test_helper"

class Mcp::Tools::ListIntegrationsTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    integration = @workspace.integrations.create!(
      kind: Integration::KIND_MCP, provider: "datadog", name: "Datadog", settings: { "server_url" => "https://dd.example/mcp" }
    )
    integration.integration_environments.create!
  end

  test "without a category it says what is connected in each, so the agent can ask which the person wants" do
    body = Mcp::Tools::ListIntegrations.perform(workspace: @workspace, args: {}).structured_content

    telemetry = body[:categories].find { |category| category[:category] == "telemetry" }
    assert_equal [ "Datadog" ], telemetry[:connected]
    assert_equal IntegrationProvider.category_list.size, body[:categories].size
  end

  test "with a category it lists every provider in it and where each stands" do
    body = Mcp::Tools::ListIntegrations.perform(workspace: @workspace, args: { category: "Telemetry" }).structured_content

    assert_equal "telemetry", body[:category]
    datadog = body[:providers].find { |provider| provider[:key] == "datadog" }
    assert_equal IntegrationProvider::STATE_CONNECTED, datadog[:state]
  end

  test "a category that does not exist is refused with the ones that do" do
    assert_raises(ArgumentError) { Mcp::Tools::ListIntegrations.perform(workspace: @workspace, args: { category: "monitoring" }) }
  end

  test "the categories are listed in its parameter, so a model picks one that exists" do
    description = Mcp::Tools::ListIntegrations.schema_for(@workspace).dig(:properties, :category, :description)

    assert_match "telemetry (Telemetry)", description
  end

  test "it reads what the integrations page reads, so it asks the same permission" do
    assert_equal [ Ability::Action::RESOURCE_INTEGRATIONS, Ability::Action::ACTION_READ ],
                 Mcp::Tools::ListIntegrations.authorization(@workspace, {})
  end
end
