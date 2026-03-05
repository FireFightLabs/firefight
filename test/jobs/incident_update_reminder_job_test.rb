require "test_helper"

class IncidentUpdateReminderJobTest < ActiveSupport::TestCase
  fixtures :workspaces, :users, :workspace_memberships, :incidents,
           :incident_lifecycle_stages, :incident_statuses, :incident_severities, :incident_roles

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:active_critical_ws1)
    @incident.update!(next_update_at: 30.minutes.from_now)
    @member = workspace_memberships(:alice_workspace_one)
  end

  test "sends reminder to incident lead" do
    @incident.incident_role_assignments.create!(
      workspace_membership: @member,
      incident_role: incident_roles(:incident_lead_ws1)
    )

    Slack::Client.expects(:post_ephemeral).once.returns({ ok: true, ts: "1234567890.123456" })

    IncidentUpdateReminderJob.perform_now(@incident.id, @incident.next_update_at.iso8601)
  end

  test "sends reminder to declared_by when no lead" do
    stub_post_ephemeral

    Slack::Client.expects(:post_ephemeral).once.returns({ ok: true, ts: "1234567890.123456" })

    IncidentUpdateReminderJob.perform_now(@incident.id, @incident.next_update_at.iso8601)
  end

  test "skips when incident not found" do
    Slack::Client.expects(:post_ephemeral).never

    IncidentUpdateReminderJob.perform_now(SecureRandom.uuid, @incident.next_update_at.iso8601)
  end

  test "skips when incident is closed" do
    expected_ts = @incident.next_update_at.iso8601
    @incident.update!(incident_status: incident_statuses(:resolved_ws1))
    Slack::Client.expects(:post_ephemeral).never

    IncidentUpdateReminderJob.perform_now(@incident.id, expected_ts)
  end

  test "skips when next_update_at has been rescheduled" do
    Slack::Client.expects(:post_ephemeral).never

    old_timestamp = 1.hour.ago.iso8601
    IncidentUpdateReminderJob.perform_now(@incident.id, old_timestamp)
  end

  test "skips when next_update_at has been cleared" do
    @incident.update!(next_update_at: nil)
    Slack::Client.expects(:post_ephemeral).never

    IncidentUpdateReminderJob.perform_now(@incident.id, 30.minutes.from_now.iso8601)
  end
end
