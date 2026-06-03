require "test_helper"

class IncidentCreationServiceTest < ActiveSupport::TestCase
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

    @service = IncidentCreationService.new(@workspace)
  end

  # create_channel

  test "create_channel creates channel and updates incident" do
    stub_create_channel(result: { channel: { id: "C_NEW", name: "inc-test", is_channel: true } })

    result = @service.create_channel(@incident)

    assert_equal "C_NEW", result[:channel_id]
    @incident.reload
    assert_equal "C_NEW", @incident.channel_id
    assert_equal "inc-test", @incident.channel_name
  end

  test "create_channel falls back on name collision" do
    Slack::Client.stubs(:create_channel)
      .raises(Slack::Client::ChannelExistsError.new("name_taken"))
      .then.returns({ channel: { id: "C_FALLBACK", name: "inc-test-fallback", is_channel: true } })

    result = @service.create_channel(@incident)

    assert_equal "C_FALLBACK", result[:channel_id]
    @incident.reload
    assert_equal "C_FALLBACK", @incident.channel_id
  end

  # set_channel_metadata

  test "set_channel_metadata sets topic and purpose" do
    @incident.update!(channel_id: "C_INC")

    Slack::Client.expects(:set_channel_topic).with(
      workspace: @workspace, channel: "C_INC",
      topic: "Severity: Critical | Status: Investigating"
    ).returns({ ok: true })
    Slack::Client.expects(:set_channel_purpose).with(
      workspace: @workspace, channel: "C_INC",
      purpose: "Incident response channel for #{@incident.identifier}"
    ).returns({ ok: true })

    result = @service.set_channel_metadata(@incident)

    assert result[:success]
  end

  # post_quick_actions_message

  test "post_quick_actions_message posts and pins message" do
    @incident.update!(channel_id: "C_INC")
    stub_post_message
    stub_pin_message

    result = @service.post_quick_actions_message(@incident)

    assert_equal "1234567890.123456", result[:message_ts]
    @incident.reload
    assert_equal "1234567890.123456", @incident.initial_message_ts
  end

  test "post_quick_actions_message skips posting when already posted" do
    @incident.update!(channel_id: "C_INC", initial_message_ts: "existing.ts")

    Slack::Client.expects(:post_message).never
    stub_pin_message

    result = @service.post_quick_actions_message(@incident)

    assert_equal "existing.ts", result[:message_ts]
  end

  # post_announcement

  test "post_announcement posts to incidents channel" do
    @incident.update!(channel_id: "C_INC")
    stub_post_message

    result = @service.post_announcement(@incident)

    assert_equal "1234567890.123456", result[:message_ts]
    @incident.reload
    assert_equal "1234567890.123456", @incident.announcement_message_ts
  end

  test "post_announcement skips when no incidents channel" do
    @workspace.update!(incidents_channel_id: nil)

    result = @service.post_announcement(@incident)

    assert result[:skipped]
  end

  test "post_announcement skips for private incidents" do
    @incident.update!(is_private: true)

    result = @service.post_announcement(@incident)

    assert result[:skipped]
  end

  test "post_announcement skips when already posted" do
    @incident.update!(announcement_message_ts: "existing.ts")

    Slack::Client.expects(:post_message).never

    result = @service.post_announcement(@incident)

    assert_equal "existing.ts", result[:message_ts]
  end

  # invite_declarer

  test "invite_declarer invites user to incident channel" do
    @incident.update!(channel_id: "C_INC")
    stub_invite_to_channel

    result = @service.invite_declarer(@incident)

    assert_equal @member.platform_user_id, result[:invited_user]
  end

  # create_incident_event

  test "create_incident_event creates event with incident update" do
    assert_difference [ "IncidentEvent.count", "IncidentUpdate.count" ], 1 do
      result = @service.create_incident_event(@incident)
      assert result[:ok]
    end

    event = @incident.incident_events.find_by!(event_type: IncidentEvent::INCIDENT_CREATED)
    assert_equal @member, event.actor
    assert_instance_of IncidentUpdate, event.eventable

    update = event.eventable
    assert_equal IncidentUpdate::CREATED, update.update_type
    assert_equal @member, update.created_by
    assert_equal @incident.incident_status, update.incident_status
    assert_equal @incident.incident_severity, update.incident_severity
  end
end
