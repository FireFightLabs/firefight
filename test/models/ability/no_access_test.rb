require "test_helper"

# No access takes a member's default away at once, outranks a set that would give it back, and is undone by revoking it.
class Ability::NoAccessTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:bob_workspace_one)
    @map = Ability::Action.system!(Ability::Action::MAP_READ)
  end

  test "a member with no access to the map reaches no environment, even through a set holding it, until it is revoked" do
    set = @workspace.ability_roles.create!(name: "Map readers")
    Ability::RoleAction.create!(role: set, action: @map)
    Ability::Grant.grant!(workspace: @workspace, principal: @member, target: { role: set })
    assert_equal({}, reach)

    grant = Ability::Grant.withhold!(workspace: @workspace, principal: @member, action: @map)
    assert_nil reach

    grant.destroy!
    assert_equal({}, reach)
  end

  test "granting the ability again turns no access into an ordinary grant that decides where" do
    Ability::Grant.withhold!(workspace: @workspace, principal: @member, action: @map)

    grant = Ability::Grant.grant!(workspace: @workspace, principal: @member, target: { action: @map },
                                  environment_ids: [ catalog_entries(:production_env).id ])

    assert_not grant.no_access?
    assert_equal({ Ability::Scope::DIMENSION_ENVIRONMENT => [ catalog_entries(:production_env).id ] }, reach)
  end

  test "only a member's default can be taken away this way" do
    refused = assert_raises(ActiveRecord::RecordInvalid) do
      Ability::Grant.withhold!(workspace: @workspace, principal: api_keys(:read_only_key), action: @map)
    end
    assert_includes refused.record.errors[:base], Ability::Grant::NO_ACCESS_ONLY_FOR_DEFAULTS
  end

  test "the API and MCP say a no access grant reaches nothing, rather than listing no environments as all" do
    grant = Ability::Grant.withhold!(workspace: @workspace, principal: @member, action: @map)

    payload = Class.new { extend Mcp::Tools::GatewayPayloads }.grant_payload(grant)

    assert payload[:no_access]
    assert_equal [], payload[:environments]
  end

  private

  def reach = AbilityGateway.reach(principal: @member, action_key: Ability::Action::MAP_READ, workspace: @workspace)
end
