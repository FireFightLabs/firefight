require "test_helper"

# A call made for a workflow run's step is ledgered with the run and the step, so the run shows it and the approval it
# waits on.
class AbilityGatewayWorkflowRunTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
    FeatureFlags.enable!(@workspace, FeatureFlags::WORKFLOWS)
    workflow = Workflow.create!(workspace: @workspace, name: "Release check")
    version = workflow.open_draft!(by: @alice)
    @run = workflow.runs.create!(workspace: @workspace, version: version, status: Workflow::Run::STATUS_RUNNING, trigger_kind: Workflow::Trigger::KIND_MANUAL,
                                 start_key: "run", started_by_kind: Workflow::Run::STARTED_BY_PERSON)
    @step = @run.steps.create!(step_key: "post", iteration: "", status: "waiting")
  end

  test "the ledger row names the run and the step, and a held call shows the step waiting on its approval" do
    policy = @workspace.policies.create!(domain: Policy::DOMAIN_APPROVALS, name: "Approvals")
    policy.policy_rules.create!(priority: 1, conditions: [ { field: "risk_level", operator: PolicyRule::OPERATOR_IS_ONE_OF, value: [ "destructive" ] } ],
                                outcome: { "require" => { "role" => WorkspaceMembership.roles[:admin], "count" => 1 } })
    context = { source: AbilityGateway::SOURCE_WEB, workflow_run_id: @run.id, workflow_step_key: "post" }

    assert_raises(AbilityGateway::PendingApproval) do
      AbilityGateway.authorize!(principal: @alice, action_key: "severities.delete", workspace: @workspace, context: context) { :deleted }
    end

    held = @step.invocations.sole
    assert_equal [ Ability::Invocation::DECISION_PENDING, "post" ], [ held.decision, held.workflow_step_key ]
    assert @step.waiting_approval?
  end
end
