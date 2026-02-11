require "test_helper"

class IncidentCreationWorkflowTest < ActiveSupport::TestCase
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
      name: "Database outage",
      summary: "Primary DB not responding",
      is_private: false
    )
  end

  test "full workflow succeeds with all steps" do
    stub_successful_slack_workflow

    workflow = IncidentCreationWorkflow.start_inline!(@incident)

    assert_equal "succeeded", workflow.state
    assert_equal 6, workflow.workflow_steps.count
    assert workflow.workflow_steps.all? { |s| s.succeeded? || s.skipped? }
  end

  test "creates channel and updates incident" do
    stub_successful_slack_workflow

    IncidentCreationWorkflow.start_inline!(@incident)

    @incident.reload
    assert_equal "C12345678", @incident.slack_channel_id
    assert_equal "incidents", @incident.slack_channel_name
  end

  test "posts quick actions and pins message" do
    stub_successful_slack_workflow

    IncidentCreationWorkflow.start_inline!(@incident)

    @incident.reload
    assert_equal "1234567890.123456", @incident.initial_message_ts
  end

  test "posts announcement to incidents channel" do
    stub_successful_slack_workflow

    IncidentCreationWorkflow.start_inline!(@incident)

    @incident.reload
    assert_equal "1234567890.123456", @incident.announcement_message_ts
  end

  test "skips announcement when no incidents channel configured" do
    @workspace.update!(incidents_channel_id: nil)
    stub_successful_slack_workflow

    workflow = IncidentCreationWorkflow.start_inline!(@incident)

    announcement_step = workflow.workflow_steps.find_by(name: "post_announcement")
    assert announcement_step.succeeded?
    assert_equal({ "skipped" => true }, announcement_step.output)

    @incident.reload
    assert_nil @incident.announcement_message_ts
  end

  test "creates incident event" do
    stub_successful_slack_workflow

    assert_difference "IncidentEvent.count", 1 do
      IncidentCreationWorkflow.start_inline!(@incident)
    end

    event = @incident.incident_events.find_by!(event_type: IncidentEvent::INCIDENT_CREATED)
    assert_equal @incident, event.incident
    assert_equal @member, event.user
    assert_equal "critical", event.metadata["severity"]
    assert_equal false, event.metadata["is_private"]
  end

  test "skips posting quick actions on retry when already posted" do
    stub_successful_slack_workflow
    @incident.update!(slack_channel_id: "C12345678", initial_message_ts: "existing.ts")

    Slack::Client.expects(:post_message).never
    Slack::Client.expects(:pin_message).once

    runner = IncidentCreationWorkflow.new
    result = runner.run_step(
      "post_quick_actions_message",
      workflow: build_workflow,
      step: nil,
      input: {}
    )

    assert_equal "existing.ts", result[:message_ts]
  end

  test "skips posting announcement on retry when already posted" do
    stub_successful_slack_workflow
    @incident.update!(announcement_message_ts: "existing.ts")

    Slack::Client.expects(:post_message).never

    runner = IncidentCreationWorkflow.new
    result = runner.run_step(
      "post_announcement",
      workflow: build_workflow,
      step: nil,
      input: {}
    )

    assert_equal "existing.ts", result[:message_ts]
  end

  test "handles channel name collision with fallback" do
    # First call raises ChannelExistsError, second succeeds
    Slack::Client.stubs(:create_channel)
      .raises(Slack::Client::ChannelExistsError.new("name_taken"))
      .then.returns({ channel: { id: "C_FALLBACK", name: "inc-001-database-outage-12345", is_channel: true } })
    stub_set_channel_topic
    stub_set_channel_purpose
    stub_invite_to_channel
    stub_post_message
    stub_pin_message

    IncidentCreationWorkflow.start_inline!(@incident)

    @incident.reload
    assert_equal "C_FALLBACK", @incident.slack_channel_id
  end

  private

  def build_workflow
    Struct.new(:subject).new(@incident)
  end
end
