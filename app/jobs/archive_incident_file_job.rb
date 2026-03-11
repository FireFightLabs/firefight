class ArchiveIncidentFileJob < ApplicationJob
  queue_as :events

  discard_on ActiveRecord::RecordNotFound

  def perform(incident_event_id, slack_file)
    incident_event = IncidentEvent.find(incident_event_id)
    return unless incident_event.event_type == IncidentEvent::MESSAGE_FILE_SHARED

    IncidentFileArchivalService.archive!(incident_event: incident_event, slack_file: slack_file)
  end
end
