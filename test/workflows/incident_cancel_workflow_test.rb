require "test_helper"

class IncidentCancelWorkflowTest < ActiveSupport::TestCase
  fixtures :workspaces, :users, :workspace_memberships, :incident_severities, :incident_lifecycle_stages, :incident_statuses

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @workspace.update!(incidents_channel_id: "C_INCIDENTS")
    @member = workspace_memberships(:alice_workspace_one)

    @incident = Incident.create!(
      workspace: @workspace,
      declared_by: @member,
      incident_status: incident_statuses(:canceled_ws1),
      incident_severity: incident_severities(:critical_ws1),
      name: "Not an incident",
      is_private: false,
      channel_id: "C_INCIDENT",
      initial_message_ts: "1234567890.111111",
      announcement_message_ts: "1234567890.222222",
      source: Incident::SOURCE_SLACK
    )
  end

  test "announces the cancel everywhere a status change is announced and attaches nothing" do
    stub_update_message
    stub_post_message
    stub_set_channel_topic
    stub_set_channel_purpose
    RunbookAttachmentService.any_instance.expects(:auto_attach).never

    workflow = IncidentCancelWorkflow.start_inline!(@incident, context: {
      updated_by_platform_user_id: @member.platform_user_id,
      message: "Duplicate of INC-041.",
      previous_status_name: "Investigating"
    })

    assert_equal "succeeded", workflow.state
    assert_equal %w[update_channel_topic update_quick_actions update_announcement post_update_message post_announcement_thread],
                 workflow.steps.order(:position).map(&:name)
    assert workflow.steps.all?(&:succeeded?)
  end
end
