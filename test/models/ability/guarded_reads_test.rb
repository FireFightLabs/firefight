require "test_helper"

# A call a provider's read guard shows to read, such as a GET through Northflank's api_request, is a read everywhere:
# held by default like any read, granted with the connection's read pack, and never held by an approval rule. A change
# through the same tool keeps every guard.
class Ability::GuardedReadsTest < ActiveSupport::TestCase
  GET = { "method" => "GET", "path" => "services/web" }.freeze
  POST = { "method" => "POST", "path" => "services/web/restart" }.freeze

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:bob_workspace_one)
    @production = catalog_entries(:production_env)
    @northflank = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "northflank", name: "Faylee")
    @northflank.integration_environments.create!(catalog_entry_id: @production.id)
    @request = @northflank.tools.create!(name: "api_request", read_only: false, enabled: true)
  end

  test "a member reads through a general tool without a grant, and a change through it still needs one" do
    assert authorize(@member, GET)
    assert_raises(AbilityGateway::Denied) { authorize(@member, POST) }
    assert @request.callable_by?(@member)
  end

  test "No access on the connection's read pack takes a member's reads through it away too" do
    Ability::Grant.withhold!(workspace: @workspace, principal: @member, role: read_pack)

    assert_raises(AbilityGateway::Denied) { authorize(@member, GET) }
    assert_not @request.callable_by?(@member)
  end

  test "a service key reads through the tool with the connection's read pack, and changes nothing with it" do
    key = api_keys(:read_only_key)
    assert_raises(AbilityGateway::Denied) { authorize(key, GET) }

    Ability::Grant.grant!(workspace: @workspace, principal: key, target: { role: read_pack })

    assert authorize(key, GET)
    assert_raises(AbilityGateway::Denied) { authorize(key, POST) }
  end

  test "an approval rule naming the tool holds its changes and never its reads" do
    policy = @workspace.policies.create!(domain: Policy::DOMAIN_APPROVALS, name: "Approvals")
    policy.policy_rules.create!(
      priority: 1, conditions: PolicyRule::ApprovalConditions.build(action_keys: [ @request.action_key ]),
      outcome: { "require" => { "role" => WorkspaceMembership.roles[:admin], "count" => 1 } }
    )
    admin = workspace_memberships(:alice_workspace_one)

    assert authorize(admin, GET)
    assert_raises(AbilityGateway::PendingApproval) { authorize(admin, POST) }
    assert_not Chat::ToolCall.held_by_rule?(workspace: @workspace, action_key: @request.action_key, scope: scope, params: GET)
    assert Chat::ToolCall.held_by_rule?(workspace: @workspace, action_key: @request.action_key, scope: scope, params: POST)
  end

  test "a rule that matches everything holds no read, a tool that only reads or one of Firefight's own, and still holds changes" do
    @workspace.find_or_create_approval_policy!.policy_rules.create!(priority: 1, conditions: [], outcome: { "require" => { "role" => "admin", "count" => 1 } })
    services = @northflank.tools.create!(name: "list_services", read_only: true, enabled: true)
    admin = workspace_memberships(:alice_workspace_one)

    assert AbilityGateway.authorize!(principal: admin, action_key: services.action_key, workspace: @workspace, scope: scope) { true }
    assert AbilityGateway.authorize!(principal: admin, action_key: Ability::Action::MAP_READ, workspace: @workspace) { true }
    assert_not Chat::ToolCall.held_by_rule?(workspace: @workspace, action_key: services.action_key, scope: scope)
    assert_raises(AbilityGateway::PendingApproval) { authorize(admin, POST) }
  end

  test "a rule cannot be saved to hold reads, and says why, while an older one that did keeps saving" do
    policy = @workspace.find_or_create_approval_policy!
    services = @northflank.tools.create!(name: "list_services", read_only: true, enabled: true)
    outcome = { "require" => { "role" => "admin", "count" => 1 } }

    by_risk = policy.policy_rules.build(priority: 1, conditions: PolicyRule::ApprovalConditions.build(risk_levels: [ Ability::Action::RISK_READ ]), outcome: outcome)
    assert_not by_risk.valid?
    assert_includes by_risk.errors[:conditions], "Reads never wait for approval, so a rule cannot hold the read risk level. Pick write or destructive."

    by_ability = policy.policy_rules.build(priority: 2, conditions: PolicyRule::ApprovalConditions.build(action_keys: [ services.action_key, @request.action_key ]), outcome: outcome)
    assert_not by_ability.valid?
    assert_includes by_ability.errors[:conditions].join, "#{services.action_key} only reads"

    older = policy.policy_rules.new(priority: 3, conditions: PolicyRule::ApprovalConditions.build(risk_levels: [ Ability::Action::RISK_READ ]), outcome: outcome)
    older.save!(validate: false)
    assert older.update(enabled: false)
  end

  test "a read is never marked as waiting where abilities are handed out" do
    services = @northflank.tools.create!(name: "list_services", read_only: true, enabled: true)

    assert services.ability_action.never_held?
    assert_not @request.ability_action.never_held?
  end

  test "the activity log records a read through the tool as a read" do
    authorize(@member, GET)

    assert_equal Ability::Action::RISK_READ, Ability::Invocation.where(workspace: @workspace, action_key: @request.action_key).sole.risk_level
  end

  private

  def scope = { "environment" => @production.id }

  def read_pack = @northflank.permission_packs.find_by!(pack: Ability::Role::PACK_READ)

  def authorize(principal, params)
    AbilityGateway.authorize!(principal: principal, action_key: @request.action_key, workspace: @workspace, scope: scope, params: params) { true }
  end
end
