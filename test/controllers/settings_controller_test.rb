require "test_helper"

class SettingsControllerTest < ActionDispatch::IntegrationTest
  fixtures :workspaces, :users, :workspace_memberships, :incident_lifecycle_stages,
           :incident_statuses, :incident_severities, :incident_types, :incidents

  setup do
    @workspace = workspaces(:slack_workspace_one)
    sign_in(users(:alice), @workspace)
  end

  test "runbooks renders every runbook with steps and conditions plus option lists" do
    runbook = @workspace.runbooks.create!(name: "Failover", summary: "Fail over the DB")
    runbook.runbook_steps.create!(title: "Promote replica", position: 1)
    runbook.incident_conditions.create!(
      workspace: @workspace,
      condition_field: IncidentCondition::FIELD_SEVERITY,
      operator: IncidentCondition::OPERATOR_ONE_OF,
      values: [ incident_severities(:critical_ws1).id ]
    )
    @workspace.runbooks.create!(name: "Archived", deleted_at: Time.current)

    get settings_runbooks_url, headers: inertia_headers
    assert_response :success

    runbooks = inertia_props["runbooks"]
    # Disabled runbooks stay listed so they can be re-enabled.
    assert_equal [ "Failover", "Archived" ], runbooks.map { |r| r["name"] }
    assert_equal [ true, false ], runbooks.map { |r| r["enabled"] }
    assert_equal [ "Promote replica" ], runbooks.first["steps"].map { |s| s["title"] }
    assert_equal 1, runbooks.first["conditions"].length

    assert inertia_props["incidentTypes"].any?
    assert inertia_props["severities"].any?
  end

  test "permissions lists every principal that can hold a grant, with its abilities" do
    integration = @workspace.integrations.create!(
      kind: Integration::KIND_MCP, provider: "planetscale", name: "PlanetScale",
      settings: { "server_url" => "https://mcp.pscale.dev/mcp/planetscale" }
    )
    integration.tools.create!(name: "list_databases", read_only: true, enabled: true)
    action = Ability::Action.find_by!(key: "planetscale.list_databases")
    member = workspace_memberships(:bob_workspace_one)
    @workspace.ability_grants.create!(principal: member, action: action, scope: {})
    @workspace.agents.create!(name: "Investigator", slug: "investigator")

    get settings_permissions_url, headers: inertia_headers
    assert_response :success

    principals = inertia_props["principals"]
    bob = principals.find { |row| row["id"] == member.id }
    assert_equal "member", bob["implicitAuthority"]
    assert_equal [ "planetscale.list_databases" ], bob["grants"].map { |grant| grant["label"] }
    assert_equal [ "action" ], bob["grants"].map { |grant| grant["kind"] }
    assert_equal "admin", principals.find { |row| row["kind"] == "user" && row["name"] == users(:alice).name }["implicitAuthority"]
    assert_includes principals.map { |row| row["kind"] }, "agent"

    assert_includes inertia_props["actions"].map { |option| option["key"] }, "planetscale.list_databases"
    assert_equal "PlanetScale", inertia_props["actions"].find { |o| o["key"] == "planetscale.list_databases" }["group"]
  end

  private

  def inertia_props
    JSON.parse(response.body)["props"]
  end
end
