require "test_helper"

class IncidentCloseWorkflowTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @workspace.update!(incidents_channel_id: "C_INCIDENTS")
    @member = workspace_memberships(:alice_workspace_one)
    @severity = incident_severities(:critical_ws1)
    @resolved_status = incident_statuses(:resolved_ws1)

    @incident = Incident.create!(
      workspace: @workspace,
      declared_by: @member,
      incident_status: @resolved_status,
      incident_severity: @severity,
      name: "Test incident",
      summary: "Fixed the issue",
      is_private: false,
      channel_id: "C_INCIDENT",
      initial_message_ts: "1234567890.111111",
      announcement_message_ts: "1234567890.222222",
      resolved_at: Time.current,
      source: Incident::SOURCE_SLACK
    )
  end

  test "full workflow succeeds" do
    stub_all_side_effects

    workflow = IncidentCloseWorkflow.start_inline!(@incident, context: workflow_context)

    assert_equal "succeeded", workflow.state
    assert_equal 6, workflow.steps.count
    assert workflow.steps.all?(&:succeeded?)
  end

  test "skips quick actions update when no initial_message_ts" do
    @incident.update!(initial_message_ts: nil)
    stub_all_side_effects

    workflow = IncidentCloseWorkflow.start_inline!(@incident, context: workflow_context)

    assert_equal "succeeded", workflow.state
  end

  test "skips announcement thread when no announcement_message_ts" do
    @incident.update!(announcement_message_ts: nil)
    stub_all_side_effects

    workflow = IncidentCloseWorkflow.start_inline!(@incident, context: workflow_context)

    assert_equal "succeeded", workflow.state
  end

  test "posts resolution message to incident channel" do
    stub_all_side_effects

    Slack::Client.expects(:post_message).at_least_once.returns({ ok: true, ts: "123.456" })

    IncidentCloseWorkflow.start_inline!(@incident, context: workflow_context)
  end

  private

  def workflow_context
    { resolved_by_platform_user_id: @member.platform_user_id }
  end

  def stub_all_side_effects
    stub_update_message
    stub_post_message
    stub_set_channel_topic
  end
end
