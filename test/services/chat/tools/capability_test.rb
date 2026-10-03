require "test_helper"

class Chat::Tools::CapabilityTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @investigation = @workspace.investigations.create!(subject: incidents(:active_critical_ws1), trigger_source: Investigation::TRIGGER_COMMAND,
                                                       max_turns: 10, max_spend_cents: 400)
    @northflank = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "northflank", name: "Northflank", slug: "northflank")
    @row = @northflank.integration_environments.create!(catalog_entry_id: catalog_entries(:production_env).id, credentials: { token: "x" }.to_json)
    @tools = %w[search_logs list_containers api_request].index_with do |name|
      @northflank.tools.create!(name: name, description: name, read_only: name != "api_request", enabled: true, params_schema: { "type" => "object" })
    end
    ResourceMap::Resource.create!(workspace: @workspace, provider: "northflank", account: "team/prod", kind: ResourceMap::KIND_SERVICE, external_id: "web-id",
                                  name: "web", integration_environment: @row, first_seen_at: Time.current, last_seen_at: Time.current)
  end

  test "Halon is offered the capability in place of the provider tool it wraps, and keeps the ones it does not" do
    grant!(@tools.values)

    names = Chat::Tools.catalog(@investigation).map(&:name)

    assert_includes names, "search_logs"
    assert_includes names, "northflank_list_containers"
    assert_not_includes names, "northflank_search_logs"
    assert_equal Chat::Tools::Groups::RESOURCES, Chat::Tools.catalog(@investigation).find { |entry| entry.name == "search_logs" }.group
  end

  test "a capability call runs as the provider's action with its own arguments, so the ledger and replay see that call" do
    grant!(@tools.values)
    Integrations::NativeExecutor.expects(:call).with { |tool:, arguments:, **| tool.name == "search_logs" && arguments == { "resource" => "web-id", "text" => "timeout" } }
                                .returns("content" => [ { "type" => "text", "text" => "2 log lines for web" } ])
    search = Chat::Tools.catalog(@investigation).find { |entry| entry.name == "search_logs" }.tool

    answer = search.call(resource: "web", text: "timeout")

    assert_match "2 log lines for web", answer
    step = @investigation.steps.find_by!(tool_name: "search_logs")
    assert_equal [ "northflank.search_logs", { "resource" => "web-id", "text" => "timeout" } ], [ step.action_key, step.params ]
  end

  test "a read never waits for the person, a change is never made while investigating, and what cannot be routed is said" do
    grant!(@tools.values)
    catalog = Chat::Tools.catalog(@investigation)

    assert_not catalog.find { |entry| entry.name == "search_logs" }.tool.requires_approval?
    restart = catalog.find { |entry| entry.name == "restart" }
    assert_equal [ Chat::Tools::STATE_READS_ONLY, nil ], [ restart.state, restart.tool ]
    assert_match "Nothing on the resource map is called checkout", catalog.find { |entry| entry.name == "search_logs" }.tool.call(resource: "checkout")
  end

  test "without a grant on any tool it would run as, the capability is listed as not granted" do
    grant!([ @tools["list_containers"] ])

    entry = Chat::Tools.catalog(@investigation).find { |each| each.name == "search_logs" }

    assert_equal [ Chat::Tools::STATE_NOT_GRANTED, nil ], [ entry.state, entry.tool ]
  end

  test "in a chat a change asks first when the tool it runs as would, and a read never does" do
    member = workspace_memberships(:alice_workspace_one)
    turn = Conversation::Turn.new(Conversation.start_personal!(workspace: @workspace, member: member), asker: member)
    catalog = Chat::Tools.catalog(turn)

    assert catalog.find { |entry| entry.name == "restart" }.tool.requires_approval?, "api_request can change anything, so a restart asks"
    assert_not catalog.find { |entry| entry.name == "search_logs" }.tool.requires_approval?
  end

  test "a connection tool that shares a capability's name is left out, here and over MCP, so neither shadows the other" do
    custom = @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: "custom_mcp", name: "Search", slug: "search",
                                             settings: { "server_url" => "https://mcp.example/mcp" })
    clash = custom.tools.create!(name: "logs", description: "Logs", read_only: true, enabled: true, params_schema: { "type" => "object" })
    grant!([ *@tools.values, clash ])

    assert_equal 1, Chat::Tools.catalog(@investigation).count { |entry| entry.name == "search_logs" }
    alice = workspace_memberships(:alice_workspace_one)
    names = Mcp::ConnectionToolFactory.tools_for(@workspace, alice).map(&:name_value) + Mcp::CapabilityToolFactory.tools_for(@workspace, alice).map(&:name_value)
    assert_equal names.uniq, names
  end

  test "a replayed run asks the provider the same thing, so the record answers the capability call" do
    grant!(@tools.values)
    Integrations::NativeExecutor.stubs(:call).returns("content" => [ { "type" => "text", "text" => "3 log lines for web" } ])
    Chat::Tools.catalog(@investigation).find { |entry| entry.name == "search_logs" }.tool.call(resource: "web", text: "timeout")
    replay = @workspace.investigations.create!(subject: @investigation.subject, trigger_source: Investigation::TRIGGER_REHEARSAL, rehearsal: true,
                                               replay_of: @investigation, max_turns: 10, max_spend_cents: 400)
    Integrations::NativeExecutor.expects(:call).never

    answer = Chat::Tools.catalog(replay).find { |entry| entry.name == "search_logs" }.tool.call(resource: "web", text: "timeout")

    assert_match "3 log lines for web", answer
  end

  private

  def grant!(tools)
    principal = @investigation.acting_principal
    tools.each { |tool| Ability::Grant.create!(workspace: @workspace, principal: principal, action: tool.reload.ability_action) }
    Ability::Resolver.bust!(principal_type: principal.class.polymorphic_name, principal_id: principal.id, workspace_id: @workspace.id)
  end
end
