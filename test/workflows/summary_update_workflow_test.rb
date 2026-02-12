require "test_helper"

class SummaryUpdateWorkflowTest < ActiveSupport::TestCase
  fixtures :workspaces, :users, :workspace_memberships, :incident_severities, :incident_statuses

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
      name: "Test incident",
      summary: "Updated summary",
      is_private: false,
      channel_id: "C_INCIDENT",
      initial_message_ts: "1234567890.111111",
      announcement_message_ts: "1234567890.222222"
    )
  end

  test "full workflow succeeds" do
    stub_update_message
    stub_post_message

    workflow = SummaryUpdateWorkflow.start_inline!(@incident, context: {
      updated_by_platform_user_id: @member.platform_user_id
    })

    assert_equal "succeeded", workflow.state
    assert_equal 3, workflow.workflow_steps.count
    assert workflow.workflow_steps.all?(&:succeeded?)
  end

  test "skips quick actions update when no initial_message_ts" do
    @incident.update!(initial_message_ts: nil)
    stub_update_message
    stub_post_message

    workflow = SummaryUpdateWorkflow.start_inline!(@incident, context: {
      updated_by_platform_user_id: @member.platform_user_id
    })

    assert_equal "succeeded", workflow.state
  end

  test "skips announcement update when no announcement_message_ts" do
    @incident.update!(announcement_message_ts: nil)
    stub_update_message
    stub_post_message

    workflow = SummaryUpdateWorkflow.start_inline!(@incident, context: {
      updated_by_platform_user_id: @member.platform_user_id
    })

    assert_equal "succeeded", workflow.state
  end

  test "posts confirmation message to incident channel" do
    stub_update_message

    Slack::Client.expects(:post_message).at_least_once.returns({ ok: true, ts: "123.456" })

    SummaryUpdateWorkflow.start_inline!(@incident, context: {
      updated_by_platform_user_id: @member.platform_user_id
    })
  end
end
