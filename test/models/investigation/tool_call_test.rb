require "test_helper"

class Investigation::ToolCallTest < ActiveSupport::TestCase
  WRITE_KEY = Ability::Action.system_key(
    Ability::Action::RESOURCE_INVESTIGATIONS, Ability::Action::ACTION_CREATE
  ).freeze

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:active_critical_ws1)
    @member = workspace_memberships(:alice_workspace_one)
    @investigation = @workspace.investigations.create!(
      incident: @incident, trigger_source: Investigation::TRIGGER_COMMAND, triggered_by: @member,
      max_turns: 10, max_tokens: 1_000, confidence_threshold: 0.7
    )
  end

  test "a tool call leaves a ledger row and the step keeps the receipt" do
    result = Investigation::ToolCall.run!(
      @investigation, principal: @member, action_key: WRITE_KEY, params: { "question" => "what changed" }
    ) { "the deploy at 10:01" }

    step = result.step
    assert_equal "the deploy at 10:01", result.value
    assert_equal InvestigationStep::STATUS_SUCCEEDED, step.status
    assert_equal "the deploy at 10:01", step.compacted_result
    assert_not_nil step.completed_at

    invocation = Ability::Invocation.find(step.invocation_id)
    assert_equal Ability::Invocation::OUTCOME_SUCCESS, invocation.outcome
    assert_equal WRITE_KEY, invocation.action_key
    assert_equal @incident.id, invocation.incident_id
  end

  test "the ledger row names who asked for the run" do
    Investigation::ToolCall.run!(@investigation, principal: @member, action_key: WRITE_KEY) { "done" }

    step = @investigation.investigation_steps.find_by!(position: 1)
    invocation = Ability::Invocation.find(step.invocation_id)

    assert_equal @member.principal_label, invocation.triggered_by_label
  end

  test "a tool that raises fails the step and the ledger row" do
    assert_raises(RuntimeError) do
      Investigation::ToolCall.run!(@investigation, principal: @member, action_key: WRITE_KEY) do
        raise "the database said no"
      end
    end

    step = @investigation.investigation_steps.find_by!(position: 1)
    assert_equal InvestigationStep::STATUS_FAILED, step.status
    assert_equal "RuntimeError", step.compacted_result

    invocation = Ability::Invocation.find(step.invocation_id)
    assert_equal Ability::Invocation::OUTCOME_ERROR, invocation.outcome
    assert_equal "RuntimeError", invocation.error_summary
  end

  test "a refused tool never runs and leaves no step open" do
    ran = false
    WorkspaceMembership.any_instance.stubs(:implicitly_allowed?).returns(false)

    assert_raises(AbilityGateway::Denied) do
      Investigation::ToolCall.run!(@investigation, principal: @member, action_key: WRITE_KEY) { ran = true }
    end

    assert_not ran
    step = @investigation.investigation_steps.find_by!(position: 1)
    assert_equal InvestigationStep::STATUS_FAILED, step.status
    assert_nil step.invocation_id
  end

  test "steps carry the theory they serve" do
    hypothesis = @investigation.hypotheses.create!(assertion: "The deploy broke it", position: 1)

    result = Investigation::ToolCall.run!(
      @investigation, principal: @member, action_key: WRITE_KEY, hypothesis: hypothesis,
      reasoning: "check what shipped"
    ) { "v41" }

    assert_equal hypothesis, result.step.hypothesis
    assert_equal "check what shipped", result.step.reasoning
  end

  test "a long result is kept whole on the step and trimmed for the running context" do
    long = "x" * (Investigation::ToolCall::MAX_COMPACTED + 500)

    step = Investigation::ToolCall.run!(
      @investigation, principal: @member, action_key: WRITE_KEY
    ) { long }.step

    assert_equal Investigation::ToolCall::MAX_COMPACTED, step.compacted_result.length
    assert_equal long, step.raw_result
  end
end
