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

  test "run_key_query is offered with a capability a check reads through, and runs as that capability's provider tool, led by its comparison" do
    northflank = @workspace.integrations.find_by!(slug: "northflank")
    northflank.tools.create!(name: "query_metrics", description: "Metrics", read_only: true, enabled: true, params_schema: { "type" => "object" })
    assert_includes Mcp::CapabilityToolFactory.tools_for(@workspace, @alice).map(&:name_value), "run_key_query"
    Integrations::NativeExecutor.expects(:call).with { |tool:, arguments:, **| tool.name == "query_metrics" && arguments == { "resource" => "web-id", "metrics" => [ "cpu" ], "minutes" => 60 } }
                                .returns("content" => [ { "type" => "text", "text" => "CPU of web" } ])

    response = Mcp::CapabilityToolFactory.key_query({ workspace: @workspace, principal: @alice }, { resource: "web", query: "cpu" })

    assert_not response.error?
    assert_equal [ "CPU of web, from Northflank. No reading came back for cpu, so it is not compared with normal.", "CPU of web" ],
                 response.content.map { |part| part[:text] || part["text"] }
    assert Ability::Invocation.exists?(workspace: @workspace, action_key: "northflank.query_metrics", source: AbilityGateway::SOURCE_MCP)
    assert_match "has no throttles check", Mcp::CapabilityToolFactory.key_query({ workspace: @workspace, principal: @alice }, { resource: "web", query: "throttles" }).content.first[:text]
  end

  test "a call is authorized and ledgered as the provider tool's action, with that tool's own arguments" do
    Integrations::NativeExecutor.expects(:call).with { |tool:, arguments:, **| tool == @search && arguments == { "resource" => "web-id" } }
                                .returns("content" => [ { "type" => "text", "text" => "no lines" } ])

    response = Mcp::CapabilityToolFactory.invoke(Integrations::Capabilities::LOGS, { workspace: @workspace, principal: @alice }, { resource: "web" })

    assert_not response.error?
    assert Ability::Invocation.exists?(workspace: @workspace, action_key: "northflank.search_logs")
  end

  test "connection all asks every connection that can answer, each authorized and ledgered as its own action" do
    datadog = @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: "datadog", name: "Datadog", slug: "datadog",
                                              settings: { "server_url" => "https://mcp.datadoghq.com/api/unstable/mcp-server/mcp" })
    datadog.integration_environments.create!
    datadog.tools.create!(name: "search_datadog_logs", description: "Logs", read_only: true, enabled: true,
                          params_schema: { "type" => "object", "properties" => { "query" => {}, "from" => {}, "to" => {} } })
    Integrations::NativeExecutor.expects(:call).returns("content" => [ { "type" => "text", "text" => "northflank lines" } ])
    Integrations::McpExecutor.expects(:call).returns("content" => [ { "type" => "text", "text" => "datadog lines" } ])

    response = Mcp::CapabilityToolFactory.invoke(Integrations::Capabilities::LOGS, { workspace: @workspace, principal: @alice },
                                                 { resource: "web", connection: "all" })

    text = response.content.first[:text]
    assert_match(/From northflank:\n.*northflank lines/m, text)
    assert_match(/From datadog:\n.*datadog lines/m, text)
    assert Ability::Invocation.exists?(workspace: @workspace, action_key: "datadog.search_datadog_logs")
    assert Ability::Invocation.exists?(workspace: @workspace, action_key: "northflank.search_logs")
    assert_not response.error?
    assert_nil response.structured_content
  end

  test "when Datadog fails, the platform answers and the agent is told so" do
    datadog = @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: "datadog", name: "Datadog", slug: "datadog",
                                              settings: { "server_url" => "https://mcp.datadoghq.com/api/unstable/mcp-server/mcp" })
    datadog.integration_environments.create!
    datadog.tools.create!(name: "search_datadog_logs", description: "Logs", read_only: true, enabled: true,
                          params_schema: { "type" => "object", "properties" => { "query" => {}, "from" => {}, "to" => {} } })
    Integrations::McpExecutor.expects(:call).raises(Integrations::Error, "Datadog is down")
    Integrations::NativeExecutor.expects(:call).returns("content" => [ { "type" => "text", "text" => "northflank lines" } ])

    response = Mcp::CapabilityToolFactory.invoke(Integrations::Capabilities::LOGS, { workspace: @workspace, principal: @alice }, { resource: "web" })

    assert_not response.error?
    assert_equal [ "datadog failed (Upstream tool failed: Datadog is down), so this is from northflank.", "northflank lines" ], response.content.map { |part| part[:text] || part["text"] }
  end

  test "under connection all the answer is an error only when every connection failed, and a refusal is named for its connection" do
    Integrations::NativeExecutor.expects(:call).raises(Integrations::Error, "Northflank is down")

    response = Mcp::CapabilityToolFactory.invoke(Integrations::Capabilities::LOGS, { workspace: @workspace, principal: @alice },
                                                 { resource: "web", connection: "all" })

    assert response.error?
    assert_match(/From northflank:\n.*Northflank is down/m, response.content.first[:text])
  end

  test "a provider that answers with its own error fails the call and is ledgered as an error" do
    Integrations::NativeExecutor.expects(:call).returns("content" => [ { "type" => "text", "text" => "Service web-id is paused" } ], "isError" => true)

    response = Mcp::CapabilityToolFactory.invoke(Integrations::Capabilities::LOGS, { workspace: @workspace, principal: @alice }, { resource: "web" })

    assert response.error?
    invocation = Ability::Invocation.find_by!(workspace: @workspace, action_key: "northflank.search_logs")
    assert_equal [ Ability::Invocation::OUTCOME_ERROR, "Service web-id is paused" ], [ invocation.outcome, invocation.error_summary ]
  end

  test "Datadog answering with its own error falls back to the platform, which answers, so the call has not failed" do
    datadog = @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: "datadog", name: "Datadog", slug: "datadog",
                                              settings: { "server_url" => "https://mcp.datadoghq.com/api/unstable/mcp-server/mcp" })
    datadog.integration_environments.create!
    datadog.tools.create!(name: "search_datadog_logs", description: "Logs", read_only: true, enabled: true,
                          params_schema: { "type" => "object", "properties" => { "query" => {}, "from" => {}, "to" => {} } })
    Integrations::McpExecutor.expects(:call).returns("content" => [ { "type" => "text", "text" => "Invalid query" } ], "isError" => true)
    Integrations::NativeExecutor.expects(:call).returns("content" => [ { "type" => "text", "text" => "northflank lines" } ])

    response = Mcp::CapabilityToolFactory.invoke(Integrations::Capabilities::LOGS, { workspace: @workspace, principal: @alice }, { resource: "web" })

    assert_not response.error?
    assert_equal [ "datadog failed (Invalid query), so this is from northflank.", "northflank lines" ], response.content.map { |part| part[:text] || part["text"] }
    outcomes = Ability::Invocation.where(workspace: @workspace).pluck(:action_key, :outcome).to_h
    assert_equal({ "datadog.search_datadog_logs" => Ability::Invocation::OUTCOME_ERROR, "northflank.search_logs" => Ability::Invocation::OUTCOME_SUCCESS }, outcomes)
  end

  test "under connection all a provider's own error counts as failing, so the answer is an error only when every one failed" do
    datadog = @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: "datadog", name: "Datadog", slug: "datadog",
                                              settings: { "server_url" => "https://mcp.datadoghq.com/api/unstable/mcp-server/mcp" })
    datadog.integration_environments.create!
    datadog.tools.create!(name: "search_datadog_logs", description: "Logs", read_only: true, enabled: true,
                          params_schema: { "type" => "object", "properties" => { "query" => {}, "from" => {}, "to" => {} } })
    Integrations::McpExecutor.stubs(:call).returns("content" => [ { "type" => "text", "text" => "Invalid query" } ], "isError" => true)
    Integrations::NativeExecutor.stubs(:call).returns("content" => [ { "type" => "text", "text" => "northflank lines" } ])
    server_context = { workspace: @workspace, principal: @alice }

    assert_not Mcp::CapabilityToolFactory.invoke(Integrations::Capabilities::LOGS, server_context, { resource: "web", connection: "all" }).error?

    Integrations::NativeExecutor.stubs(:call).returns("content" => [ { "type" => "text", "text" => "Service web-id is paused" } ], "isError" => true)
    assert Mcp::CapabilityToolFactory.invoke(Integrations::Capabilities::LOGS, server_context, { resource: "web", connection: "all" }).error?
  end

  test "a resource nothing holds is said, not sent" do
    response = Mcp::CapabilityToolFactory.invoke(Integrations::Capabilities::LOGS, { workspace: @workspace, principal: @alice }, { resource: "checkout" })

    assert response.error?
  end
end
