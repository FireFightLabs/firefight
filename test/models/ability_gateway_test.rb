require "test_helper"

class AbilityGatewayTest < ActiveSupport::TestCase
  fixtures :workspaces, :users, :workspace_memberships, :api_keys, :ability_actions, :ability_grants

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @key = api_keys(:read_only_key)
    @membership = workspace_memberships(:alice_workspace_one)
  end

  def create_approval_policy
    policy = @workspace.policies.create!(domain: Policy::DOMAIN_APPROVALS, name: "Approvals")
    policy.policy_rules.create!(
      priority: 1,
      conditions: [ { field: "risk_level", operator: PolicyRule::OPERATOR_IS_ONE_OF, value: [ "destructive" ] } ],
      outcome: { "require" => { "role" => WorkspaceMembership.roles[:admin], "count" => 1 } }
    )
    policy
  end

  test "allowed reads execute without a ledger row" do
    result = assert_no_difference "Ability::Invocation.count" do
      AbilityGateway.authorize!(principal: @key, action_key: "incidents.read", workspace: @workspace) { :payload }
    end

    assert_equal :payload, result
  end

  test "denials raise and always write a ledger row" do
    error = assert_difference "Ability::Invocation.count", 1 do
      assert_raises(AbilityGateway::Denied) do
        AbilityGateway.authorize!(principal: @key, action_key: "incidents.create", workspace: @workspace)
      end
    end

    invocation = Ability::Invocation.find_by!(action_key: "incidents.create", principal_id: @key.id)
    assert_equal Ability::Invocation::DECISION_DENY, invocation.decision
    assert_equal @key.principal_label, invocation.principal_label
    assert invocation.completed_at.present?
    assert_equal "incidents.create", error.action_key
  end

  test "unknown action keys are denied" do
    assert_raises(AbilityGateway::Denied) do
      AbilityGateway.authorize!(principal: @key, action_key: "nonsense.read", workspace: @workspace)
    end
  end

  test "write-risk executions get a write-ahead row finalized on success" do
    key = api_keys(:full_access_key)

    AbilityGateway.authorize!(principal: key, action_key: "incidents.create", workspace: @workspace,
                              context: { incident_id: nil, triggered_by_label: "user:Alice" }) { :created }

    invocation = Ability::Invocation.find_by!(action_key: "incidents.create", principal_id: key.id)
    assert_equal Ability::Invocation::DECISION_ALLOW, invocation.decision
    assert_equal Ability::Invocation::OUTCOME_SUCCESS, invocation.outcome
    assert_equal "user:Alice", invocation.triggered_by_label
    assert invocation.completed_at.present?
    assert invocation.idempotency_key.present?
    assert_not_nil invocation.duration_ms
  end

  test "a crash mid-execution leaves the outcome-unknown signal via error finalize" do
    key = api_keys(:full_access_key)

    assert_raises(RuntimeError) do
      AbilityGateway.authorize!(principal: key, action_key: "catalog.delete", workspace: @workspace) do
        raise "boom"
      end
    end

    invocation = Ability::Invocation.find_by!(action_key: "catalog.delete", principal_id: key.id)
    assert_equal Ability::Invocation::OUTCOME_ERROR, invocation.outcome
    assert_equal "RuntimeError", invocation.error_summary
  end

  test "handle mode defers finalize to the caller" do
    key = api_keys(:full_access_key)

    authorization = AbilityGateway.authorize!(principal: key, action_key: "incidents.update", workspace: @workspace)
    invocation = Ability::Invocation.find_by!(action_key: "incidents.update", principal_id: key.id)
    assert_nil invocation.completed_at

    authorization.finalize_success!
    assert_equal Ability::Invocation::OUTCOME_SUCCESS, invocation.reload.outcome

    assert_raises(Ability::Invocation::AlreadyFinalized) { invocation.finalize!(outcome: Ability::Invocation::OUTCOME_ERROR) }
  end

  test "memberships hold implicit system reads but not writes" do
    assert_equal :ok, AbilityGateway.authorize!(principal: @membership, action_key: "alerts.read",
                                                workspace: @workspace) { :ok }

    assert_raises(AbilityGateway::Denied) do
      AbilityGateway.authorize!(principal: @membership, action_key: "alerts.create", workspace: @workspace)
    end
  end

  test "a matching approval policy parks the call as pending" do
    key = api_keys(:full_access_key)
    create_approval_policy

    error = assert_raises(AbilityGateway::PendingApproval) do
      AbilityGateway.authorize!(principal: key, action_key: "catalog.delete", workspace: @workspace) { :never }
    end

    approval = error.approval
    assert approval.pending?
    assert_equal WorkspaceMembership.roles[:admin], approval.required_role
    assert_equal Ability::Approval.digest("catalog.delete", {}, {}), approval.request_digest

    pending_row = Ability::Invocation.find_by!(approval_id: approval.id)
    assert_equal Ability::Invocation::DECISION_PENDING, pending_row.decision

    resurfaced = assert_raises(AbilityGateway::PendingApproval) do
      AbilityGateway.authorize!(principal: key, action_key: "catalog.delete", workspace: @workspace,
                                context: { approval_id: approval.id })
    end
    assert_equal approval.id, resurfaced.approval.id
    assert_equal 1, Ability::Approval.count
  end

  test "an approved approval admits exactly the approved call, once" do
    key = api_keys(:full_access_key)
    create_approval_policy

    error = assert_raises(AbilityGateway::PendingApproval) do
      AbilityGateway.authorize!(principal: key, action_key: "catalog.delete", workspace: @workspace)
    end
    approval = error.approval
    approval.approve!(by: @membership)

    result = AbilityGateway.authorize!(principal: key, action_key: "catalog.delete", workspace: @workspace,
                                       context: { approval_id: approval.id }) { :executed }
    assert_equal :executed, result

    executed = Ability::Invocation.find_by!(approval_id: approval.id, decision: Ability::Invocation::DECISION_ALLOW)
    assert_equal Ability::Invocation::OUTCOME_SUCCESS, executed.outcome
    assert approval.reload.consumed_at.present?

    assert_raises(AbilityGateway::PendingApproval) do
      AbilityGateway.authorize!(principal: key, action_key: "catalog.delete", workspace: @workspace,
                                context: { approval_id: approval.id })
    end
  end

  test "approvals bind to the exact request digest" do
    key = api_keys(:full_access_key)
    create_approval_policy

    approval = assert_raises(AbilityGateway::PendingApproval) do
      AbilityGateway.authorize!(principal: key, action_key: "catalog.delete", workspace: @workspace,
                                params: { slug: "checkout" })
    end.approval
    approval.approve!(by: @membership)

    assert_raises(AbilityGateway::PendingApproval) do
      AbilityGateway.authorize!(principal: key, action_key: "catalog.delete", workspace: @workspace,
                                params: { slug: "payments" }, context: { approval_id: approval.id })
    end
    assert_nil approval.reload.consumed_at
  end

  test "a denied approval denies the retry" do
    key = api_keys(:full_access_key)
    create_approval_policy

    approval = assert_raises(AbilityGateway::PendingApproval) do
      AbilityGateway.authorize!(principal: key, action_key: "catalog.delete", workspace: @workspace)
    end.approval
    approval.deny!(by: @membership)

    assert_raises(AbilityGateway::Denied) do
      AbilityGateway.authorize!(principal: key, action_key: "catalog.delete", workspace: @workspace,
                                context: { approval_id: approval.id })
    end
  end

  test "scoped grants deny requests outside their scope" do
    key = api_keys(:read_only_key)
    Ability::Grant.create!(workspace: @workspace, principal: key, action: ability_actions(:alerts_create),
                           scope: { "environment" => [ "env-prod" ] })

    assert_equal :ok, AbilityGateway.authorize!(principal: key, action_key: "alerts.create", workspace: @workspace,
                                                scope: { "environment" => "env-prod" }) { :ok }

    assert_raises(AbilityGateway::Denied) do
      AbilityGateway.authorize!(principal: key, action_key: "alerts.create", workspace: @workspace,
                                scope: { "environment" => "env-dev" })
    end
  end
end
