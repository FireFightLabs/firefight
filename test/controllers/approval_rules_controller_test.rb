require "test_helper"

class ApprovalRulesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @bob = workspace_memberships(:bob_workspace_one)
    sign_in(users(:alice), @workspace)
  end

  def rule_params(overrides = {})
    {
      action_keys: [ "catalog.delete" ], risk_levels: [], environments: [],
      approver_role: WorkspaceMembership.roles[:admin], self_approval: false,
      notify: PolicyRule::ApprovalOutcome::NOTIFY_BOTH, approvers: [ @bob.id ]
    }.merge(overrides)
  end

  test "the first rule creates the approval policy and is rendered on the permissions page" do
    assert_nil @workspace.approval_policy

    post approval_rules_url, params: { rule: rule_params }

    assert_redirected_to gateway_permissions_path
    assert_equal "Approval rule was created.", flash[:notice]
    rule = @workspace.approval_rules.first!
    assert_equal [ "catalog.delete" ], PolicyRule::ApprovalConditions.values_for(rule.conditions, "action_key")
    requirement = rule.outcome["require"]
    assert_equal [ @bob.id ], requirement["approvers"]
    assert_equal false, requirement["self_approval"]
    assert_equal PolicyRule::ApprovalOutcome::NOTIFY_BOTH, requirement["notify"]

    get gateway_permissions_url, headers: inertia_headers
    rendered = inertia_props["approvalRules"].first
    assert_equal rule.id, rendered["id"]
    assert_equal [ @bob.id ], rendered["approverIds"]
    assert_equal "both", rendered["notify"]
    assert inertia_props["members"].any? { |member| member["id"] == @bob.id }
  end

  test "approvers must belong to the workspace" do
    post approval_rules_url, params: { rule: rule_params(approvers: [ workspace_memberships(:alice_workspace_two).id ]) }, headers: inertia_headers

    assert_equal 0, @workspace.approval_rules.count
  end

  test "update replaces the rule and a bare enabled flag only toggles it" do
    post approval_rules_url, params: { rule: rule_params }
    rule = @workspace.approval_rules.first!

    patch approval_rule_url(rule), params: { rule: rule_params(approvers: [], risk_levels: [ "destructive" ]) }
    rule.reload
    assert_equal "Approval rule was updated.", flash[:notice]
    assert_equal [], rule.outcome["require"]["approvers"]
    assert_equal [ "destructive" ], PolicyRule::ApprovalConditions.values_for(rule.conditions, "risk_level")

    patch approval_rule_url(rule), params: { rule: { enabled: false } }
    rule.reload
    assert_not rule.enabled?
    assert_equal [ "destructive" ], PolicyRule::ApprovalConditions.values_for(rule.conditions, "risk_level")
  end

  test "rules reorder and delete" do
    post approval_rules_url, params: { rule: rule_params(action_keys: [ "first.one" ]) }
    post approval_rules_url, params: { rule: rule_params(action_keys: [ "second.one" ]) }
    first, second = @workspace.approval_rules.to_a

    patch move_up_approval_rule_url(second)
    assert_equal "Approval rule was moved up.", flash[:notice]
    assert_equal [ second, first ], @workspace.approval_rules.to_a

    delete approval_rule_url(first)
    assert_equal "Approval rule was deleted.", flash[:notice]
    assert_equal [ second ], @workspace.approval_rules.to_a
  end

  test "a rule from another workspace is not reachable" do
    other = workspaces(:slack_workspace_two)
    rule = other.find_or_create_approval_policy!.policy_rules.create!(
      priority: 1, conditions: [], outcome: { "require" => { "role" => "admin", "count" => 1 } }
    )

    delete approval_rule_url(rule)

    assert_response :not_found
    assert rule.reload.persisted?
  end
end
