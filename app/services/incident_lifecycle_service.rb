class IncidentLifecycleService
  attr_reader :workspace

  def initialize(workspace)
    @workspace = workspace
  end

  def create(attrs)
    incident = Incident.create!(**attrs, workspace: workspace)

    if incident.source == Incident::SOURCE_SLACK
      IncidentCreationService.new(workspace).create_channel(incident)
    end

    IncidentCreationWorkflow.start!(incident)
    incident
  end

  def update(incident, attrs, changed_by:, message: nil)
    previous_status_name = incident.incident_status.name
    previous_severity_name = incident.incident_severity.name
    previous_type_name = incident.incident_type&.name

    incident.record_change!(IncidentEvent::INCIDENT_UPDATED, changed_by: changed_by, message: message) do
      incident.update!(attrs)
    end

    IncidentUpdateWorkflow.start!(incident, context: {
      updated_by_platform_user_id: changed_by&.platform_user_id,
      message: message,
      previous_status_name: previous_status_name,
      previous_severity_name: previous_severity_name,
      previous_type_name: previous_type_name
    })
  end

  def close(incident, attrs, changed_by:)
    lead = attrs.delete(:lead)

    incident.record_change!(IncidentEvent::INCIDENT_RESOLVED, changed_by: changed_by) do
      incident.update!(attrs)
      incident.lead = lead if lead
    end

    IncidentTranscriptCache.expire_after_close!(incident)

    IncidentCloseWorkflow.start!(incident, context: {
      resolved_by_platform_user_id: changed_by&.platform_user_id
    })

    if workspace.archive_channel_enabled && incident.channel_id.present?
      ChannelArchivalJob.set(wait: workspace.archive_channel_delay_minutes.minutes)
        .perform_later(incident.id, incident.resolved_at.iso8601)
    end
  end

  def reopen(incident, attrs, changed_by:, reason: nil)
    incident.record_change!(IncidentEvent::INCIDENT_REOPENED, changed_by: changed_by, message: reason, details: reason ? { reason: reason } : nil) do
      incident.update!(attrs)
    end

    IncidentTranscriptCache.clear_expiry!(incident)

    if incident.channel_archived_at.present?
      workspace.adapter.unarchive_channel(channel_id: incident.channel_id)
      incident.update!(channel_archived_at: nil, channel_archived_by: nil)
    end

    IncidentReopenWorkflow.start!(incident, context: {
      reopened_by_platform_user_id: changed_by&.platform_user_id,
      reason: reason
    })
  end

  def accept(incident, attrs, changed_by:)
    incident.record_change!(IncidentEvent::INCIDENT_ACCEPTED, changed_by: changed_by) do
      incident.update!(attrs)
      incident.lead = changed_by unless incident.lead
    end

    IncidentUpdateWorkflow.start!(incident, context: {
      updated_by_platform_user_id: changed_by&.platform_user_id
    })
  end

  def assign_lead(incident, lead, changed_by:)
    incident.record_change!(IncidentEvent::LEAD_ASSIGNED, changed_by: changed_by) do
      incident.lead = lead
    end

    LeadAssignmentWorkflow.start!(incident, context: {
      lead_platform_user_id: lead&.platform_user_id
    })
  end
end
