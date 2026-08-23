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
    @tool = integration.tools.create!(name: "list_databases", read_only: true, enabled: true)
    @action = Ability::Action.find_by!(key: "planetscale.list_databases")

    sign_in(users(:alice), @workspace)
  end

  test "granting a tool action scoped to an environment lets the call through only there" do
    post ability_grants_url, params: {
      principal_type: "WorkspaceMembership", principal_id: @member.id,
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
      principal_type: "WorkspaceMembership", principal_id: @member.id,
      action_id: @action.id, environment_ids: []
    }

    assert_equal({}, @member.ability_grants.find_by!(action_id: @action.id).scope)
  end

  test "granting the same action again retargets rather than duplicating" do
    post ability_grants_url, params: {
      principal_type: "WorkspaceMembership", principal_id: @member.id,
      action_id: @action.id, environment_ids: [ @production.id ]
    }
    post ability_grants_url, params: {
      principal_type: "WorkspaceMembership", principal_id: @member.id,
      action_id: @action.id, environment_ids: [ @development.id ]
    }

    grants = @member.ability_grants.where(action_id: @action.id)
    assert_equal 1, grants.count
    assert_equal({ "environment" => [ @development.id ] }, grants.sole.scope)
  end

  test "a catalog entry that is not an environment cannot enter a scope" do
    post ability_grants_url, params: {
      principal_type: "WorkspaceMembership", principal_id: @member.id,
      action_id: @action.id, environment_ids: [ catalog_entries(:vendor_acme).id ]
    }

    assert_equal({}, @member.ability_grants.find_by!(action_id: @action.id).scope)
  end

  test "a principal from another workspace is not found" do
    outsider = workspace_memberships(:alice_workspace_two)

    post ability_grants_url, params: {
      principal_type: "WorkspaceMembership", principal_id: outsider.id,
      action_id: @action.id, environment_ids: []
    }

    assert_response :not_found
    assert_empty outsider.ability_grants
  end

  test "an unknown principal type is refused rather than constantized" do
    post ability_grants_url, params: {
      principal_type: "User", principal_id: users(:alice).id,
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

  test "members cannot manage grants" do
    sign_in(users(:bob), @workspace)

    post ability_grants_url, params: {
      principal_type: "WorkspaceMembership", principal_id: @member.id,
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
