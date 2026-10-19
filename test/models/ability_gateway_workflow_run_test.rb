require "test_helper"

# A call made for a workflow run's step is ledgered with the run and the step, so the run shows it and the approval it
# waits on.
class AbilityGatewayWorkflowRunTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
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

  test "a step of a run a person confirmed in a chat is approved by that yes when they may approve it, and asked otherwise" do
    @workspace.find_or_create_approval_policy!.policy_rules.create!(priority: 1, conditions: [], outcome: { "require" => { "role" => "admin", "count" => 1 } })
    bob = workspace_memberships(:bob_workspace_one)
    context = { source: AbilityGateway::SOURCE_WORKFLOW, workflow_run_id: @run.id, workflow_step_key: "post" }

    @run.update!(confirmed_by: @alice)
    assert_equal :deleted, AbilityGateway.authorize!(principal: @alice, action_key: "severities.delete", workspace: @workspace, context: context) { :deleted }
    approval = @workspace.ability_approvals.sole
    assert_equal [ Ability::Approval::STATUS_APPROVED, @alice ], [ approval.status, approval.approver ]

    @run.update!(confirmed_by: bob)
    assert_raises(AbilityGateway::PendingApproval) do
      AbilityGateway.authorize!(principal: @alice, action_key: "severities.update", workspace: @workspace, context: context) { :updated }
    end
  end

  test "a change to who may do what in a confirmed run still waits for a person's own approval" do
    @run.update!(confirmed_by: @alice)
    agent = Agent.create!(workspace: @workspace, name: "Release bot", slug: "release_bot")
    Ability::Grant.create!(workspace: @workspace, principal: agent, action: Ability::Action.lookup("webhooks.create", @workspace))
    context = { source: AbilityGateway::SOURCE_WORKFLOW, workflow_run_id: @run.id, workflow_step_key: "post", asks_a_person: true }

    assert_raises(AbilityGateway::PendingApproval) do
      AbilityGateway.authorize!(principal: agent, action_key: "webhooks.create", workspace: @workspace, context: context) { :created }
    end
  end
end
