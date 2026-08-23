require "test_helper"

class IncidentCreationWorkflowTest < ActiveSupport::TestCase
  fixtures :workspaces, :users, :workspace_memberships, :incident_severities, :incident_lifecycle_stages, :incident_statuses

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
      is_private: false,
      source: Incident::SOURCE_SLACK
    )
  end

  test "full workflow succeeds with all steps" do
    stub_successful_slack_workflow

    workflow = IncidentCreationWorkflow.start_inline!(@incident)

    assert_equal "succeeded", workflow.state
    assert_equal 8, workflow.steps.count
    assert workflow.steps.all? { |s| s.succeeded? || s.skipped? }
  end

  test "attach_runbooks auto-attaches matching runbooks on incident creation" do
    stub_successful_slack_workflow
    runbook = @workspace.runbooks.create!(name: "Auto attach me")
    runbook.incident_conditions.create!(
      workspace: @workspace,
      condition_field: IncidentCondition::FIELD_SEVERITY,
      operator: IncidentCondition::OPERATOR_ONE_OF,
      values: [ @severity.id ]
    )

    workflow = IncidentCreationWorkflow.start_inline!(@incident)

    assert workflow.steps.find_by!(name: "attach_runbooks").succeeded?
    assert @incident.incident_runbooks.exists?(runbook: runbook)
  end

  test "invite_responders invites resolved members and no-ops without context" do
    stub_successful_slack_workflow
    stub_invite_to_channel
    member = workspace_memberships(:alice_workspace_one)

    workflow = IncidentCreationWorkflow.start_inline!(@incident, context: { invite_membership_ids: [ member.id ] })
    step = workflow.steps.find_by!(name: "invite_responders")
    assert step.succeeded?
    assert_equal [ member.platform_user_id ], step.output["invited_users"]

    bare_incident = @incident.dup.tap do |incident|
      incident.assign_attributes(sequence_number: @incident.sequence_number + 1,
                                 identifier: "INC-#{@incident.sequence_number + 1}", channel_id: nil)
      incident.save!
    end
    bare = IncidentCreationWorkflow.start_inline!(bare_incident)
    assert_equal({ "skipped" => true }, bare.steps.find_by!(name: "invite_responders").output)
  end

  test "creates channel and updates incident" do
    stub_successful_slack_workflow

    IncidentCreationWorkflow.start_inline!(@incident)

    @incident.reload
    assert_equal "C12345678", @incident.channel_id
    assert_equal "incidents", @incident.channel_name
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

    announcement_step = workflow.steps.find_by(name: "post_announcement")
    assert announcement_step.succeeded?
    assert_equal({ "skipped" => true }, announcement_step.output)

    @incident.reload
    assert_nil @incident.announcement_message_ts
  end

  test "creates incident event with initial update" do
    stub_successful_slack_workflow

    assert_difference [ "IncidentEvent.count", "IncidentUpdate.count" ], 1 do
      IncidentCreationWorkflow.start_inline!(@incident)
    end

    event = @incident.incident_events.find_by!(event_type: IncidentEvent::INCIDENT_CREATED)
    assert_equal @incident, event.incident
    assert_equal @member, event.actor
    assert_instance_of IncidentUpdate, event.eventable
    assert_equal IncidentUpdate::CREATED, event.eventable.update_type
    assert_equal @incident.incident_severity, event.eventable.incident_severity
  end

  test "skips posting quick actions on retry when already posted" do
    stub_successful_slack_workflow
    @incident.update!(channel_id: "C12345678", initial_message_ts: "existing.ts")

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
      .raises(AdapterError::ChannelExists.new("name_taken"))
      .then.returns({ channel: { id: "C_FALLBACK", name: "inc-001-database-outage-12345", is_channel: true } })
    stub_set_channel_topic
    stub_set_channel_purpose
    stub_invite_to_channel
    stub_post_message
    stub_pin_message

    IncidentCreationWorkflow.start_inline!(@incident)

    @incident.reload
    assert_equal "C_FALLBACK", @incident.channel_id
  end

  private

  def build_workflow
    Struct.new(:subject).new(@incident)
  end
end
