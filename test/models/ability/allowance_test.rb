require "test_helper"

# An entry of what Halon may do without asking names one risky change, through a capability or one connection's tool,
# kept to a connection or an environment, and reads the way a person says it.
class Ability::AllowanceTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @github = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "github", name: "GitHub", slug: "github")
    @merge = tool!(@github, "merge_pull_request")
    @production = catalog_entries(:production_env)
  end

  def tool!(integration, name, read_only: false)
    integration.tools.create!(name: name, description: name, enabled: true, read_only: read_only, params_schema: {})
  end

  test "an entry reads as a person says it" do
    rollback = @workspace.allowances.create!(capability: Integrations::Capabilities::ROLLBACK, environment: @production)
    merge = @workspace.allowances.create!(action: @merge.ability_action)
    restart = @workspace.allowances.create!(capability: Integrations::Capabilities::RESTART, integration: @github)

    assert_equal "Roll back deploys in Production", rollback.sentence
    assert_equal "Merge pull request on GitHub", merge.sentence
    assert_equal "Restart services and databases on GitHub", restart.sentence
  end

  test "an entry names one change, never both or neither, and once per place" do
    assert_not @workspace.allowances.new.valid?
    assert_not @workspace.allowances.new(capability: Integrations::Capabilities::ROLLBACK, action: @merge.ability_action).valid?
    assert_not @workspace.allowances.new(action: @merge.ability_action, integration: @github).valid?, "a tool already names its connection"
    @workspace.allowances.create!(capability: Integrations::Capabilities::SCALE)
    assert_not @workspace.allowances.new(capability: Integrations::Capabilities::SCALE).valid?
    assert @workspace.allowances.new(capability: Integrations::Capabilities::SCALE, environment: @production).valid?
  end

  test "a read, Firefight's own change, a general tool, a statement that writes rows and a tool on a remote server are refused" do
    read = tool!(@github, "list_issues", read_only: true)
    northflank = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "northflank", name: "Northflank", slug: "northflank")
    general = tool!(northflank, "api_request")
    linear = @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: "linear", name: "Linear", slug: "linear", settings: { "server_url" => "https://mcp.linear.app/mcp" })
    remote = tool!(linear, "save_issue")
    planetscale = @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: "planetscale", name: "PlanetScale", slug: "planetscale",
                                                  settings: { "server_url" => "https://mcp.pscale.dev/mcp/planetscale" })
    writes = tool!(planetscale, "planetscale_execute_write_query")

    assert_match "only reads", Ability::Allowance.refusal_for(read.ability_action)
    assert_match "Only a change through a connection's tool", Ability::Allowance.refusal_for(Ability::Action.lookup("incidents.delete", @workspace))
    assert_match "reaches a whole API", Ability::Allowance.refusal_for(general.ability_action)
    assert_match "cannot see inside", Ability::Allowance.refusal_for(remote.ability_action)
    assert Ability::Allowance.refusal_for(writes.ability_action), "a statement that writes rows is refused"
    assert_nil Ability::Allowance.refusal_for(@merge.ability_action)
  end

  test "covering finds the enabled entry for a tool or a capability, kept to its connection and environment" do
    action = @merge.ability_action
    by_tool = @workspace.allowances.create!(action: action, environment: @production)
    render = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "render", name: "Render", slug: "render")
    restart = tool!(render, "restart_service").ability_action
    by_capability = @workspace.allowances.create!(capability: Integrations::Capabilities::RESTART, integration: render)

    assert_equal by_tool, Ability::Allowance.covering(@workspace, action: action, environment_id: @production.id)
    assert_nil Ability::Allowance.covering(@workspace, action: action, environment_id: nil)
    assert_equal by_capability, Ability::Allowance.covering(@workspace, action: restart, environment_id: nil, capability: Integrations::Capabilities::RESTART,
                                                                        integration_id: render.id)
    assert_nil Ability::Allowance.covering(@workspace, action: restart, environment_id: nil), "a capability's entry covers only a call made through it"
    assert_nil Ability::Allowance.covering(@workspace, action: restart, environment_id: nil, capability: Integrations::Capabilities::ROLLBACK, integration_id: render.id)
  end

  test "an entry Halon acted under stays for the record and is turned off instead" do
    entry = @workspace.allowances.create!(action: @merge.ability_action)
    assert_nil entry.delete_blocked_reason

    Ability::Invocation.create!(workspace: @workspace, principal: workspace_memberships(:alice_workspace_one), principal_label: "Alice", action_key: @merge.action_key,
                                decision: Ability::Invocation::DECISION_ALLOW, idempotency_key: SecureRandom.uuid, allowance: entry,
                                unasked_reason: Ability::Invocation::UNASKED_ALLOWANCE)

    reloaded = @workspace.allowances.with_usage_counts.find(entry.id)
    assert_equal 1, reloaded.usage_count
    assert_equal "Halon made 1 change under this, so it stays for the record. Turn it off instead.", reloaded.delete_blocked_reason
  end

  test "a token never changes the list" do
    assert_equal Ability::Allowance::TOKEN_CHANGE_REFUSAL, Ability::Allowance.change_blocked_reason(AbilityGateway::SOURCE_API)
    assert_equal Ability::Allowance::TOKEN_CHANGE_REFUSAL, Ability::Allowance.change_blocked_reason(AbilityGateway::SOURCE_MCP)
    assert_nil Ability::Allowance.change_blocked_reason(AbilityGateway::SOURCE_WEB)
  end
end
