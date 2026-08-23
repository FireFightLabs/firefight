require "test_helper"

class IncidentReopenWorkflowTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @workspace.update!(incidents_channel_id: "C_INCIDENTS")
    @member = workspace_memberships(:alice_workspace_one)
    @severity = incident_severities(:critical_ws1)
    @status = incident_statuses(:investigating_ws1)

    @incident = Incident.create!(
      workspace: @workspace,
      declared_by: @member,
      incident_status: @status,
      incident_severity: @severity,
      name: "Reopened incident",
      is_private: false,
      channel_id: "C_INCIDENT",
      initial_message_ts: "1234567890.111111",
      announcement_message_ts: "1234567890.222222",
      source: Incident::SOURCE_SLACK
    )
  end

  test "full workflow succeeds" do
    stub_all_side_effects

    workflow = IncidentReopenWorkflow.start_inline!(@incident, context: workflow_context)

    assert_equal "succeeded", workflow.state
    assert_equal 5, workflow.steps.count
    assert workflow.steps.all?(&:succeeded?)
  end

  test "skips quick actions update when no initial_message_ts" do
    @incident.update!(initial_message_ts: nil)
    stub_all_side_effects

    workflow = IncidentReopenWorkflow.start_inline!(@incident, context: workflow_context)

    assert_equal "succeeded", workflow.state
  end

  test "skips announcement thread when no announcement_message_ts" do
    @incident.update!(announcement_message_ts: nil)
    stub_all_side_effects

    workflow = IncidentReopenWorkflow.start_inline!(@incident, context: workflow_context)

    assert_equal "succeeded", workflow.state
  end

  test "posts reopen message to incident channel" do
    stub_all_side_effects

    Slack::Client.expects(:post_message).at_least_once.returns({ ok: true, ts: "123.456" })

    IncidentReopenWorkflow.start_inline!(@incident, context: workflow_context)
  end

  test "passes reason through to reopen messages" do
    stub_all_side_effects

    ctx = { reopened_by_platform_user_id: @member.platform_user_id, reason: "Issue is still occurring" }
    workflow = IncidentReopenWorkflow.start_inline!(@incident, context: ctx)

    assert_equal "succeeded", workflow.state
    assert_equal "Issue is still occurring", workflow.context["reason"]
  end

  private

  def workflow_context
    { reopened_by_platform_user_id: @member.platform_user_id, reason: "Issue recurring" }
  end

  def stub_all_side_effects
    stub_update_message
    stub_post_message
    stub_set_channel_topic
  end
end
