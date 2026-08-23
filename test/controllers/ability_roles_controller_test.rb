require "test_helper"

class AbilityRolesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:bob_workspace_one)
    @production = catalog_entries(:production_env)

    integration = @workspace.integrations.create!(
      kind: Integration::KIND_MCP, provider: "planetscale", name: "PlanetScale",
      settings: { "server_url" => "https://mcp.pscale.dev/mcp/planetscale" }
    )
    integration.integration_environments.create!(catalog_entry_id: @production.id)
    integration.tools.create!(name: "list_databases", read_only: true, enabled: true)
    integration.tools.create!(name: "get_database", read_only: true, enabled: true)
    @list = Ability::Action.find_by!(key: "planetscale.list_databases")
    @get = Ability::Action.find_by!(key: "planetscale.get_database")

    sign_in(users(:alice), @workspace)
  end

  test "a set is created with a slug derived from its name" do
    post ability_roles_url, params: { name: "Database read-only" }

    assert_equal "database_read_only", @workspace.ability_roles.sole.slug
  end

  test "syncing a set replaces its contents rather than accumulating" do
    role = @workspace.ability_roles.create!(name: "Database read-only")

    patch ability_role_url(role), params: { action_ids: [ @list.id, @get.id ] }
    assert_equal [ @get.id, @list.id ].sort, role.reload.role_actions.map(&:action_id).sort

    patch ability_role_url(role), params: { action_ids: [ @list.id ] }
    assert_equal [ @list.id ], role.reload.role_actions.map(&:action_id)
  end

  test "granting a set carries every ability in it, under the grant's scope" do
    role = @workspace.ability_roles.create!(name: "Database read-only")
    role.sync_actions!([ @list.id, @get.id ])

    post ability_grants_url, params: {
      principal_type: "WorkspaceMembership", principal_id: @member.id,
      role_id: role.id, environment_ids: [ @production.id ]
    }

    [ @list, @get ].each do |action|
      assert AbilityGateway.authorize!(
        principal: @member, action_key: action.key, workspace: @workspace,
        scope: { "environment" => @production.id }
      ) { true }
    end
  end

  test "an ability added to a granted set reaches its holders immediately" do
    role = @workspace.ability_roles.create!(name: "Database read-only")
    role.sync_actions!([ @list.id ])
    @workspace.ability_grants.create!(principal: @member, role: role, scope: {})

    assert_raises(AbilityGateway::Denied) do
      AbilityGateway.authorize!(principal: @member, action_key: @get.key, workspace: @workspace,
                                scope: { "environment" => @production.id }) { true }
    end

    patch ability_role_url(role), params: { action_ids: [ @list.id, @get.id ] }

    assert AbilityGateway.authorize!(
      principal: @member, action_key: @get.key, workspace: @workspace,
      scope: { "environment" => @production.id }
    ) { true }
  end

  test "deleting a set revokes it everywhere it was granted" do
    role = @workspace.ability_roles.create!(name: "Database read-only")
    role.sync_actions!([ @list.id ])
    @workspace.ability_grants.create!(principal: @member, role: role, scope: {})

    delete ability_role_url(role)

    assert_empty @member.ability_grants.reload
    assert_raises(AbilityGateway::Denied) do
      AbilityGateway.authorize!(principal: @member, action_key: @list.key, workspace: @workspace,
                                scope: { "environment" => @production.id }) { true }
    end
  end

  test "an action from another workspace cannot be put into a set" do
    role = @workspace.ability_roles.create!(name: "Database read-only")
    foreign = Ability::Action.create!(
      workspace: workspaces(:slack_workspace_two), kind: Ability::Action::KIND_TOOL,
      key: "other.tool", risk_level: Ability::Action::RISK_READ
    )

    patch ability_role_url(role), params: { action_ids: [ foreign.id ] }

    assert_empty role.reload.role_actions
  end

  test "clearing the last ability out of a set actually empties it" do
    role = @workspace.ability_roles.create!(name: "Database read-only")
    role.sync_actions!([ @list.id ])

    patch ability_role_url(role), params: { action_ids: [] }
    assert_empty role.reload.role_actions, "unticking the last ability must persist"

    role.sync_actions!([ @list.id ])
    patch ability_role_url(role)
    assert_empty role.reload.role_actions, "an omitted list means the set covers nothing"
  end

  test "members cannot manage sets" do
    sign_in(users(:bob), @workspace)

    post ability_roles_url, params: { name: "Everything" }

    assert_empty @workspace.ability_roles
  end

  private

  def sign_in(user, workspace)
    ApplicationController.any_instance.stubs(:current_user).returns(user)
    ApplicationController.any_instance.stubs(:current_workspace).returns(workspace)
    ApplicationController.any_instance.stubs(:user_signed_in?).returns(true)
  end
end
