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
    # Tools that change something, since a member reads every connected tool without a grant.
    integration.tools.create!(name: "create_branch", read_only: false, enabled: true)
    integration.tools.create!(name: "merge_branch", read_only: false, enabled: true)
    @list = Ability::Action.find_by!(key: "planetscale.create_branch")
    @get = Ability::Action.find_by!(key: "planetscale.merge_branch")

    sign_in(users(:alice), @workspace)
  end

  test "a set is created with a slug derived from its name" do
    post ability_roles_url, params: { name: "Database read-only" }

    assert_equal "database_read_only", @workspace.ability_roles.hand_made.sole.slug
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
      principal_kind: "user", principal_id: @member.id,
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

    assert_empty @workspace.ability_roles.hand_made
  end

  test "a built-in pack refuses a hand edit or a delete with a toast saying why" do
    changes = @workspace.ability_roles.find_by!(pack: Ability::Role::PACK_CHANGES)

    patch ability_role_url(changes), params: { action_ids: [] }
    assert_equal changes.edit_blocked_reason, flash[:alert]
    delete ability_role_url(changes)
    assert_equal changes.delete_blocked_reason, flash[:alert]
    assert_equal [ @get.id, @list.id ].sort, changes.reload.role_actions.map(&:action_id).sort
  end

  test "the page lists built-in packs apart from hand-made sets, each with what it covers and why it cannot be edited" do
    @workspace.ability_roles.create!(name: "Database helpers")

    get gateway_permissions_url, headers: inertia_headers

    sets = inertia_props["sets"]
    assert_equal [ "Database helpers" ], sets.reject { |set| set["builtIn"] }.map { |set| set["name"] }
    pack = sets.find { |set| set["name"] == "PlanetScale: changes" }
    assert_equal [ true, "Every tool on PlanetScale that changes something." ], pack.values_at("builtIn", "description")
    assert_match "cannot be changed by hand", pack["editBlockedReason"]
    assert_includes sets.map { |set| set["name"] }, Ability::Role::CHANGES_EVERYWHERE_NAME
  end

  test "creating, changing and deleting a set each say so" do
    post ability_roles_url, params: { name: "Database helpers" }
    assert_equal "Database helpers was created.", flash[:notice]

    role = @workspace.ability_roles.find_by!(name: "Database helpers")
    patch ability_role_url(role), params: { action_ids: [ @list.id ] }
    assert_equal "Database helpers was updated.", flash[:notice]

    delete ability_role_url(role)
    assert_equal "Database helpers was deleted.", flash[:notice]
  end

  test "deleting a set that is held says it was revoked from everyone holding it" do
    role = @workspace.ability_roles.create!(name: "Database helpers")
    @workspace.ability_grants.create!(principal: @member, role: role, scope: {})

    delete ability_role_url(role)

    assert_equal "Database helpers was deleted and revoked from everyone who held it.", flash[:notice]
  end

  test "each set counts the people, keys and agents holding it" do
    role = @workspace.ability_roles.create!(name: "Database helpers")
    @workspace.ability_grants.create!(principal: @member, role: role, scope: {})
    @workspace.ability_grants.create!(principal: workspace_memberships(:alice_workspace_one), role: role, scope: {})
    @workspace.ability_grants.create!(principal: api_keys(:full_access_key), role: role, scope: {})
    agent = @workspace.agents.create!(name: "Deploy bot", slug: "deploy_bot")
    @workspace.ability_grants.create!(principal: agent, role: role, scope: {})

    get gateway_permissions_url, headers: inertia_headers

    set = inertia_props["sets"].find { |entry| entry["name"] == "Database helpers" }
    assert_equal [ 2, 1, 1 ], set.values_at("peopleCount", "keyCount", "agentCount")
  end

  private

  def sign_in(user, workspace)
    ApplicationController.any_instance.stubs(:current_user).returns(user)
    ApplicationController.any_instance.stubs(:current_workspace).returns(workspace)
    ApplicationController.any_instance.stubs(:user_signed_in?).returns(true)
  end
end
