require "test_helper"

class Interactions::RunbookStepHandlersTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:alice_workspace_one)
    @other = workspace_memberships(:bob_workspace_one)

    @runbook = @workspace.runbooks.create!(name: "Database outage response")
    @step = @runbook.runbook_steps.create!(title: "Check connection pool", instruction: "Look at the pool", position: 1)
    @second_step = @runbook.runbook_steps.create!(title: "Failover to replica", position: 2)

    @incident = Incident.create!(
      workspace: @workspace,
      declared_by: @member,
      incident_status: incident_statuses(:investigating_ws1),
      incident_severity: incident_severities(:critical_ws1),
      name: "Test incident",
      is_private: false,
      channel_id: "C_TEST_INCIDENT",
      source: Incident::SOURCE_SLACK
    )

    stub_post_message
    stub_get_permalink
    @incident_runbook = RunbookAttachmentService.new(@workspace).attach(incident: @incident, runbook: @runbook)
    stub_update_message
  end

  test "claiming a step creates one action assigned to the clicker and posts nothing" do
    Slack::Client.expects(:post_message).never

    assert_difference "@incident.incident_actions.count", 1 do
      Interactions::ClaimRunbookStepHandler.execute(claim_interaction(@step))
    end

    action = @incident.incident_actions.find_by!(runbook_step: @step)
    assert_equal @member, action.assignee
    assert_equal @step.title, action.description
    assert_nil action.message_ts
  end

  test "claiming the same step twice leaves one action" do
    Interactions::ClaimRunbookStepHandler.execute(claim_interaction(@step))

    assert_no_difference "@incident.incident_actions.count" do
      Interactions::ClaimRunbookStepHandler.execute(claim_interaction(@step))
    end
  end

  test "completing a claimed step redraws the runbook message" do
    Interactions::ClaimRunbookStepHandler.execute(claim_interaction(@step))
    action = @incident.incident_actions.find_by!(runbook_step: @step)

    Slack::Client.expects(:update_message).at_least_once
    Interactions::MarkActionDoneHandler.execute(done_interaction(action))

    assert action.reload.done?
  end

  test "assigning a step from the modal creates the action and announces it" do
    Slack::Client.expects(:post_message).at_least_once.returns({ ok: true, ts: "1.1" })

    Interactions::AssignRunbookStepHandler.execute(assign_interaction(@step, @other))

    action = @incident.incident_actions.find_by!(runbook_step: @step)
    assert_equal @other, action.assignee
  end

  test "assigning a claimed step hands it to the new person" do
    Interactions::ClaimRunbookStepHandler.execute(claim_interaction(@step))
    Slack::Client.expects(:post_message).at_least_once.returns({ ok: true, ts: "1.1" })

    Interactions::AssignRunbookStepHandler.execute(assign_interaction(@step, @other))

    action = @incident.incident_actions.find_by!(runbook_step: @step)
    assert_equal @other, action.assignee
    assert @incident.incident_events.exists?(event_type: IncidentEvent::ACTION_REASSIGNED)
  end

  test "the retired apply button redraws the message instead of creating actions" do
    Slack::Client.expects(:update_message).at_least_once

    assert_no_difference "@incident.incident_actions.count" do
      Interactions::ApplyRunbookHandler.execute(apply_interaction(@incident_runbook.id))
    end
  end

  test "an action from another workspace cannot be reassigned" do
    Interactions::ClaimRunbookStepHandler.execute(claim_interaction(@step))
    action = @incident.incident_actions.find_by!(runbook_step: @step)
    outsider = workspaces(:slack_workspace_two)

    interaction = Interaction.new(
      platform: Platforms::SLACK, type: Interaction::BLOCK_ACTIONS,
      team_id: outsider.platform_id,
      user_id: workspace_memberships(:alice_workspace_two).platform_user_id,
      action_id: Identifiers::REASSIGN_ACTION,
      block_id: "#{Identifiers::ACTION_BLOCK_PREFIX}#{action.id}",
      selected_user: workspace_memberships(:alice_workspace_two).platform_user_id
    )

    assert_nil Interactions::ReassignActionHandler.execute(interaction)
    assert_equal @member, action.reload.assignee
  end

  test "a missing incident runbook is handled silently" do
    assert_nil Interactions::ApplyRunbookHandler.execute(apply_interaction(SecureRandom.uuid))
  end

  private

  def claim_interaction(step)
    build_interaction(
      action_id: Identifiers::CLAIM_RUNBOOK_STEP,
      action_value: { incident_runbook_id: @incident_runbook.id, step_id: step.id }.to_json
    )
  end

  def done_interaction(action)
    build_interaction(action_id: Identifiers::MARK_ACTION_DONE, action_value: action.id)
  end

  def apply_interaction(incident_runbook_id)
    build_interaction(action_id: Identifiers::APPLY_RUNBOOK, action_value: incident_runbook_id)
  end

  def assign_interaction(step, assignee)
    build_interaction(
      action_id: Identifiers::ASSIGN_RUNBOOK_STEP,
      block_id: "#{Identifiers::RUNBOOK_STEP_BLOCK_PREFIX}#{step.id}",
      private_metadata: Slack::PrivateMetadata.encode(incident_id: @incident.id, incident_runbook_id: @incident_runbook.id),
      selected_user: assignee.platform_user_id
    )
  end

  def build_interaction(attrs)
    Interaction.new({
      platform: Platforms::SLACK,
      type: Interaction::BLOCK_ACTIONS,
      team_id: @workspace.platform_id,
      user_id: @member.platform_user_id,
      trigger_id: "12345.trigger"
    }.merge(attrs))
  end
end
