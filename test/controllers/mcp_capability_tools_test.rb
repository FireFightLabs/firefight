require "test_helper"

class McpCapabilityToolsTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
    northflank = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "northflank", name: "Northflank", slug: "northflank")
    row = northflank.integration_environments.create!(catalog_entry_id: catalog_entries(:production_env).id, credentials: { token: "x" }.to_json)
    @search = northflank.tools.create!(name: "search_logs", description: "Logs", read_only: true, enabled: true, params_schema: { "type" => "object" })
    ResourceMap::Resource.create!(workspace: @workspace, provider: "northflank", account: "team/prod", kind: ResourceMap::KIND_SERVICE, external_id: "web-id",
                                  name: "web", integration_environment: row, first_seen_at: Time.current, last_seen_at: Time.current)
  end

  test "an outside agent is offered the capabilities it could call, beside the provider tools" do
    assert_equal [ "search_logs" ], Mcp::CapabilityToolFactory.tools_for(@workspace, @alice).map(&:name_value)
    assert_empty Mcp::CapabilityToolFactory.tools_for(@workspace, workspace_memberships(:bob_workspace_one))
  end

  test "a call is authorized and ledgered as the provider tool's action, with that tool's own arguments" do
    Integrations::NativeExecutor.expects(:call).with { |tool:, arguments:, **| tool == @search && arguments == { "resource" => "web-id" } }
                                .returns("content" => [ { "type" => "text", "text" => "no lines" } ])

    response = Mcp::CapabilityToolFactory.invoke(Integrations::Capabilities::LOGS, { workspace: @workspace, principal: @alice }, { resource: "web" })

    assert_not response.error?
    assert Ability::Invocation.exists?(workspace: @workspace, action_key: "northflank.search_logs")
  end

  test "a resource nothing holds is said, not sent" do
    response = Mcp::CapabilityToolFactory.invoke(Integrations::Capabilities::LOGS, { workspace: @workspace, principal: @alice }, { resource: "checkout" })

    assert response.error?
  end
end
