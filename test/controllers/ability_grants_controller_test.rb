require "test_helper"

class AbilityGrantsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:bob_workspace_one)
    @production = catalog_entries(:production_env)
    @development = catalog_entries(:development_env)

    integration = @workspace.integrations.create!(
      kind: Integration::KIND_MCP, provider: "planetscale", name: "PlanetScale",
      settings: { "server_url" => "https://mcp.pscale.dev/mcp/planetscale" }
    )
    integration.integration_environments.create!(catalog_entry_id: @production.id)
    # A tool that changes something, since a member reads every connected tool without a grant.
    @tool = integration.tools.create!(name: "create_branch", read_only: false, enabled: true)
    @action = Ability::Action.find_by!(key: "planetscale.create_branch")

    sign_in(users(:alice), @workspace)
  end

  test "granting a tool action scoped to an environment lets the call through only there" do
    post ability_grants_url, params: {
      principal_kind: "user", principal_id: @member.id,
      action_id: @action.id, environment_ids: [ @production.id ]
    }

    grant = @member.ability_grants.find_by!(action_id: @action.id)
    assert_equal({ "environment" => [ @production.id ] }, grant.scope)

    assert AbilityGateway.authorize!(
      principal: @member, action_key: @action.key, workspace: @workspace,
      scope: { "environment" => @production.id }
    ) { true }
  end

  test "a grant scoped to one environment denies another" do
    @workspace.ability_grants.create!(
      principal: @member, action: @action, scope: { "environment" => [ @development.id ] }
    )

    assert_raises(AbilityGateway::Denied) do
      AbilityGateway.authorize!(
        principal: @member, action_key: @action.key, workspace: @workspace,
        scope: { "environment" => @production.id }
      ) { true }
    end
  end

  test "an empty environment list means unrestricted rather than nothing" do
    post ability_grants_url, params: {
      principal_kind: "user", principal_id: @member.id,
      action_id: @action.id, environment_ids: []
    }

    assert_equal({}, @member.ability_grants.find_by!(action_id: @action.id).scope)
  end

  test "granting the same action again retargets rather than duplicating" do
    post ability_grants_url, params: {
      principal_kind: "user", principal_id: @member.id,
      action_id: @action.id, environment_ids: [ @production.id ]
    }
    post ability_grants_url, params: {
      principal_kind: "user", principal_id: @member.id,
      action_id: @action.id, environment_ids: [ @development.id ]
    }

    grants = @member.ability_grants.where(action_id: @action.id)
    assert_equal 1, grants.count
    assert_equal({ "environment" => [ @development.id ] }, grants.sole.scope)
  end

  test "a catalog entry that is not an environment cannot enter a scope" do
    post ability_grants_url, params: {
      principal_kind: "user", principal_id: @member.id,
      action_id: @action.id, environment_ids: [ catalog_entries(:vendor_acme).id ]
    }

    assert_equal({}, @member.ability_grants.find_by!(action_id: @action.id).scope)
  end

  test "a principal from another workspace is not found" do
    outsider = workspace_memberships(:alice_workspace_two)

    post ability_grants_url, params: {
      principal_kind: "user", principal_id: outsider.id,
      action_id: @action.id, environment_ids: []
    }

    assert_response :not_found
    assert_empty outsider.ability_grants
  end

  test "an unknown principal type is refused rather than constantized" do
    post ability_grants_url, params: {
      principal_kind: "person", principal_id: users(:alice).id,
      action_id: @action.id, environment_ids: []
    }

    assert_response :not_found
  end

  test "revoking removes the grant and the ability with it" do
    grant = @workspace.ability_grants.create!(principal: @member, action: @action, scope: {})

    delete ability_grant_url(grant)

    assert_not Ability::Grant.exists?(grant.id)
    assert_raises(AbilityGateway::Denied) do
      AbilityGateway.authorize!(
        principal: @member, action_key: @action.key, workspace: @workspace,
        scope: { "environment" => @production.id }
      ) { true }
    end
  end

  test "retargeting a grant's environments updates its scope" do
    grant = @workspace.ability_grants.create!(
      principal: @member, action: @action, scope: { "environment" => [ @production.id ] }
    )

    patch ability_grant_url(grant), params: { environment_ids: [ @development.id ] }

    assert_equal({ "environment" => [ @development.id ] }, grant.reload.scope)
  end

  test "no access takes a member's default away at once, says so, and restoring gives it back with a toast too" do
    halon = Ability::Action.system!(Ability::Action::INVESTIGATIONS_CREATE)

    post withhold_ability_grants_url, params: { principal_kind: "user", principal_id: @member.id, action_id: halon.id }

    assert_equal "Bob Jones can no longer ask Halon and start investigations. Restore it to give it back.", flash[:notice]
    assert_not @member.may?(Ability::Action::RESOURCE_INVESTIGATIONS, Ability::Action::ACTION_CREATE, @workspace)
    grant = @member.ability_grants.find_by!(action: halon)
    assert grant.no_access?

    delete ability_grant_url(grant)

    assert_equal "Bob Jones can ask Halon and start investigations again.", flash[:notice]
    assert @member.may?(Ability::Action::RESOURCE_INVESTIGATIONS, Ability::Action::ACTION_CREATE, @workspace)
  end

  test "no access takes a connection's reads away as one row, and restoring gives them back, each with a toast" do
    reads = @tool.integration.tools.create!(name: "list_databases", read_only: true, enabled: true)
    pack = @tool.integration.permission_packs.find_by!(pack: Ability::Role::PACK_READ)

    get gateway_permissions_url, headers: inertia_headers
    bob = inertia_props["principals"].find { |principal| principal["id"] == @member.id }
    assert_equal [ "set", pack.id, "PlanetScale: read", WorkspaceMembership::DEFAULT_NOTES[WorkspaceMembership::DEFAULT_HELD] ],
                 bob["defaultAccess"].find { |access| access["kind"] == "set" }.values_at("kind", "targetId", "title", "note")

    post withhold_ability_grants_url, params: { principal_kind: "user", principal_id: @member.id, role_id: pack.id }
    assert_equal "Bob Jones can no longer read PlanetScale's tools. Restore it to give it back.", flash[:notice]
    assert_not @member.permitted_to?(reads.ability_action, @workspace)

    delete ability_grant_url(@member.ability_grants.find_by!(role: pack))
    assert_equal "Bob Jones can read PlanetScale's tools again.", flash[:notice]
    assert @member.permitted_to?(reads.ability_action, @workspace)
  end

  test "giving a person a pack from the quick grant panel goes back to the page it came from with a toast" do
    pack = @tool.integration.permission_packs.find_by!(pack: Ability::Role::PACK_CHANGES)

    post ability_grants_url, params: { principal_kind: "user", principal_id: @member.id, role_id: pack.id, environment_ids: [] },
                             headers: { "Referer" => integrations_url }

    assert_redirected_to integrations_url
    assert_equal "user:Bob Jones was granted PlanetScale: changes.", flash[:notice]
    assert_equal({}, @member.ability_grants.find_by!(role: pack).scope)
  end

  test "no access is refused for an ability members do not hold by default, and for an admin, with why" do
    post withhold_ability_grants_url, params: { principal_kind: "user", principal_id: @member.id, action_id: @action.id }
    assert_equal Ability::Grant::NO_ACCESS_ONLY_FOR_DEFAULTS, flash[:alert]

    map = Ability::Action.system!(Ability::Action::MAP_READ)
    post withhold_ability_grants_url, params: { principal_kind: "user", principal_id: workspace_memberships(:alice_workspace_one).id, action_id: map.id }
    assert_equal Ability::Grant::NO_ACCESS_NOT_FOR_ADMINS, flash[:alert]

    assert_empty Ability::Grant.where(workspace: @workspace).select(&:no_access?)
  end

  test "a no access row offers no environments or expiry to change" do
    grant = Ability::Grant.withhold!(workspace: @workspace, principal: @member, action: Ability::Action.system!(Ability::Action::MAP_READ))

    patch ability_grant_url(grant), params: { environment_ids: [ @production.id ] }

    assert_equal Ability::Grant::NO_ACCESS_HAS_NO_REACH, flash[:alert]
    assert grant.reload.no_access?
  end

  test "the page lists what a member holds without a grant, and a no access row only there" do
    Ability::Grant.withhold!(workspace: @workspace, principal: @member, action: Ability::Action.system!(Ability::Action::MAP_READ))

    get gateway_permissions_url, headers: inertia_headers

    bob = inertia_props["principals"].find { |principal| principal["id"] == @member.id }
    assert_equal [ [ Ability::Action::MAP_READ, WorkspaceMembership::DEFAULT_NOTES[WorkspaceMembership::DEFAULT_NO_ACCESS] ],
                   [ Ability::Action::INVESTIGATIONS_CREATE, WorkspaceMembership::DEFAULT_NOTES[WorkspaceMembership::DEFAULT_HELD] ] ],
                 bob["defaultAccess"].map { |access| access.values_at("actionKey", "note") }
    assert_empty bob["grants"]
    alice = inertia_props["principals"].find { |principal| principal["id"] == workspace_memberships(:alice_workspace_one).id }
    assert_empty alice["defaultAccess"]
  end

  test "members cannot manage grants" do
    sign_in(users(:bob), @workspace)

    post ability_grants_url, params: {
      principal_kind: "user", principal_id: @member.id,
      action_id: @action.id, environment_ids: []
    }

    assert_empty @member.ability_grants
  end

  private

  def sign_in(user, workspace)
    ApplicationController.any_instance.stubs(:current_user).returns(user)
    ApplicationController.any_instance.stubs(:current_workspace).returns(workspace)
    ApplicationController.any_instance.stubs(:user_signed_in?).returns(true)
  end
end
