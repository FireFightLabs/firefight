require "test_helper"

class Incident::SnapshotsTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:alice_workspace_one)

    @incident = Incident.create!(
      workspace: @workspace,
      declared_by: @member,
      incident_status: incident_statuses(:investigating_ws1),
      incident_severity: incident_severities(:critical_ws1),
      name: "Attribution test incident",
      is_private: false,
      channel_id: "C_ATTRIBUTION",
      source: Incident::SOURCE_SLACK
    )
  end

  test "plumbing written outside record_change! never lands in another actor's changed_fields" do
    Incident.find(@incident.id).update!(
      channel_archived_at: Time.current,
      channel_archived_by: "system",
      initial_message_ts: "1234.5678"
    )

    @incident.record_change!(IncidentEvent::INCIDENT_UPDATED, by: @member) do
      @incident.update!(summary: "A real change by a person")
    end

    update = @incident.incident_updates.find_by!(update_type: IncidentUpdate::UPDATED)
    assert_equal [ "summary" ], update.changed_fields
    assert_not_nil update.channel_archived_at, "the snapshot still captures the current plumbing state"
  end
end
