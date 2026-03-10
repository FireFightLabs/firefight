require "test_helper"

class ArchiveIncidentFileJobTest < ActiveJob::TestCase
  fixtures :incident_events, :incidents, :incident_statuses, :incident_severities, :incident_lifecycle_stages, :workspace_memberships, :workspaces, :users

  test "archives file for message file shared events" do
    incident_event = incident_events(:inc1_created)
    incident_event.update!(event_type: IncidentEvent::MESSAGE_FILE_SHARED)

    IncidentFileArchivalService.expects(:archive!).with(
      incident_event: incident_event,
      slack_file: { "id" => "F123" }
    )

    ArchiveIncidentFileJob.perform_now(incident_event.id, { "id" => "F123" })
  end

  test "ignores non-file-shared events" do
    incident_event = incident_events(:inc1_created)

    IncidentFileArchivalService.expects(:archive!).never

    ArchiveIncidentFileJob.perform_now(incident_event.id, { "id" => "F123" })
  end
end
