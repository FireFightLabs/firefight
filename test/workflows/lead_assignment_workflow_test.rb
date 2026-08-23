require "test_helper"

class LeadAssignmentWorkflowTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @workspace.update!(incidents_channel_id: "C_INCIDENTS")
    @member = workspace_memberships(:alice_workspace_one)
    @bob = workspace_memberships(:bob_workspace_one)
    @severity = incident_severities(:critical_ws1)
    @status = incident_statuses(:investigating_ws1)

    @incident = Incident.create!(
      workspace: @workspace,
      declared_by: @member,
      incident_status: @status,
      incident_severity: @severity,
      name: "Test incident",
      summary: "Test summary",
      is_private: false,
      channel_id: "C_INCIDENT",
      initial_message_ts: "1234567890.111111",
      announcement_message_ts: "1234567890.222222",
      source: Incident::SOURCE_SLACK
    )

    @incident.lead = @bob
  end

  test "full workflow succeeds" do
    stub_all_side_effects

    workflow = LeadAssignmentWorkflow.start_inline!(@incident, context: {
      lead_platform_user_id: @bob.platform_user_id
    })

    assert_equal "succeeded", workflow.state
    assert_equal 5, workflow.steps.count
    assert workflow.steps.all?(&:succeeded?)
  end

  test "updates channel topic with lead name" do
    stub_all_side_effects

    Slack::Client.expects(:set_channel_topic).with(
      has_entries(topic: includes("Lead: #{@bob.user.name}"))
    ).returns({ ok: true, topic: "test" })

    LeadAssignmentWorkflow.start_inline!(@incident, context: {
      lead_platform_user_id: @bob.platform_user_id
    })
  end

  test "posts lead expectations as ephemeral" do
    stub_all_side_effects

    Slack::Client.expects(:post_ephemeral).with(
      has_entries(
        user: @bob.platform_user_id,
        text: includes("Incident Lead")
      )
    ).returns({ ok: true, ts: "123.456" })

    LeadAssignmentWorkflow.start_inline!(@incident, context: {
      lead_platform_user_id: @bob.platform_user_id
    })
  end

  test "posts lead announcement to channel" do
    stub_all_side_effects

    Slack::Client.expects(:post_message).with(
      has_entries(
        channel: @incident.channel_id,
        text: includes(@bob.platform_user_id)
      )
    ).at_least_once.returns({ ok: true, ts: "123.456" })

    LeadAssignmentWorkflow.start_inline!(@incident, context: {
      lead_platform_user_id: @bob.platform_user_id
    })
  end

  private

  def stub_all_side_effects
    stub_set_channel_topic
    stub_set_channel_purpose
    stub_update_message
    stub_post_message
    stub_post_ephemeral
  end
end
