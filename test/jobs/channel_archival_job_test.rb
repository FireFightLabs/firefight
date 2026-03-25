require "test_helper"

class ChannelArchivalJobTest < ActiveSupport::TestCase
  fixtures :workspaces, :users, :workspace_memberships,
           :incident_lifecycle_stages, :incident_statuses, :incident_severities

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @workspace.update!(archive_channel_enabled: true, archive_channel_delay_minutes: 60)
    @member = workspace_memberships(:alice_workspace_one)
    @resolved_status = incident_statuses(:resolved_ws1)

    @incident = Incident.create!(
      workspace: @workspace,
      declared_by: @member,
      incident_status: @resolved_status,
      incident_severity: incident_severities(:critical_ws1),
      name: "Test incident",
      is_private: false,
      channel_id: "C_TEST",
      resolved_at: Time.current,
      source: Incident::SOURCE_SLACK
    )
  end

  test "archives channel for closed incident" do
    Slack::Client.expects(:archive_channel).once.returns({ ok: true })

    ChannelArchivalJob.perform_now(@incident.id, @incident.resolved_at.iso8601)

    @incident.reload
    assert_not_nil @incident.channel_archived_at
    assert_equal "system", @incident.channel_archived_by
  end

  test "skips when incident no longer closed" do
    @incident.update!(incident_status: incident_statuses(:investigating_ws1), resolved_at: nil)
    Slack::Client.expects(:archive_channel).never

    ChannelArchivalJob.perform_now(@incident.id, Time.current.iso8601)
  end

  test "skips when resolved_at does not match" do
    Slack::Client.expects(:archive_channel).never

    ChannelArchivalJob.perform_now(@incident.id, 1.hour.ago.iso8601)
  end

  test "skips when archival disabled on workspace" do
    @workspace.update!(archive_channel_enabled: false)
    Slack::Client.expects(:archive_channel).never

    ChannelArchivalJob.perform_now(@incident.id, @incident.resolved_at.iso8601)
  end

  test "skips when already archived" do
    @incident.update!(channel_archived_at: Time.current, channel_archived_by: "system")
    Slack::Client.expects(:archive_channel).never

    ChannelArchivalJob.perform_now(@incident.id, @incident.resolved_at.iso8601)
  end

  test "skips when incident not found" do
    Slack::Client.expects(:archive_channel).never

    ChannelArchivalJob.perform_now(SecureRandom.uuid, Time.current.iso8601)
  end

  test "handles already archived error gracefully" do
    Slack::Client.expects(:archive_channel).raises(Slack::Client::AlreadyArchivedError.new("already archived"))

    ChannelArchivalJob.perform_now(@incident.id, @incident.resolved_at.iso8601)

    @incident.reload
    assert_not_nil @incident.channel_archived_at
  end
end
