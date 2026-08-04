class IncidentLifecycleService
  class RoleNotUnassignable < StandardError; end

  attr_reader :workspace

  def initialize(workspace)
    @workspace = workspace
  end

  def create(create_channel_sync: false, workflow_context: {}, **attrs)
    incident = Incident.create!(**attrs, workspace: workspace)

    IncidentCreationService.new(workspace).create_channel(incident) if create_channel_sync

    IncidentCreationWorkflow.start!(incident, context: workflow_context)
    incident
  end

  def update(incident, attrs, changed_by:, message: nil)
    previous_status_name = incident.incident_status.name
    previous_severity_name = incident.incident_severity.name
    previous_type_name = incident.incident_type&.name

    incident.record_change!(IncidentEvent::INCIDENT_UPDATED, by: changed_by, message: message) do
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

    incident.record_change!(IncidentEvent::INCIDENT_RESOLVED, by: changed_by) do
      incident.update!(attrs)
      incident.lead = lead if lead
    end

    IncidentCloseWorkflow.start!(incident, context: {
      resolved_by_platform_user_id: changed_by&.platform_user_id
    })

    if workspace.archive_channel_enabled && incident.channel_id.present?
      ChannelArchivalJob.set(wait: workspace.archive_channel_delay_minutes.minutes)
        .perform_later(incident.id, incident.resolved_at.iso8601)
    end
  end

  # A canceled incident was never an incident, so it deliberately does not get
  # what closing gets: no resolved_at, which keeps it out of time-to-resolve, no
  # postmortem, which gates on the closed stage, and no close workflow, since
  # there is nothing to follow up. The channel still archives, because a channel
  # for a false positive is pure noise.
  def cancel(incident, attrs, changed_by:, message: nil)
    previous_status_name = incident.incident_status.name

    incident.record_change!(IncidentEvent::INCIDENT_CANCELED, by: changed_by, message: message) do
      incident.update!(attrs)
    end

    # The same announcement path a status change takes, so the channel topic,
    # the pinned quick actions, and the announcement all reflect that this is
    # over. Skipping it left cancelling completely silent.
    IncidentUpdateWorkflow.start!(incident, context: {
      updated_by_platform_user_id: changed_by&.platform_user_id,
      previous_status_name: previous_status_name,
      message: message
    })

    if workspace.archive_channel_enabled && incident.channel_id.present?
      ChannelArchivalJob.set(wait: workspace.archive_channel_delay_minutes.minutes)
        .perform_later(incident.id)
    end
  end

  def reopen(incident, attrs, changed_by:, reason: nil)
    incident.record_change!(
      IncidentEvent::INCIDENT_REOPENED,
      by: changed_by,
      message: reason,
      metadata: reason ? { reason: reason } : nil
    ) do
      incident.update!(attrs)
    end

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
    incident.record_change!(IncidentEvent::INCIDENT_ACCEPTED, by: changed_by) do
      incident.update!(attrs)
      incident.lead = changed_by unless incident.lead
    end

    IncidentUpdateWorkflow.start!(incident, context: {
      updated_by_platform_user_id: changed_by&.platform_user_id
    })
  end

  def assign_lead(incident, lead, changed_by:)
    incident.record_change!(IncidentEvent::LEAD_ASSIGNED, by: changed_by) do
      incident.lead = lead
    end

    LeadAssignmentWorkflow.start!(incident, context: {
      lead_platform_user_id: lead&.platform_user_id
    })
  end

  # Takes role => member (a nil member clears the role) and applies every
  # change in one pass, so a modal that touches several roles announces once.
  # The lead keeps its own path, which already updates the channel topic,
  # quick actions and announcement.
  def assign_roles(incident, assignments, changed_by:)
    applied = assignments.reject { |role, member| incident.role_holder(role) == member }
    return applied if applied.empty?

    applied.each do |role, member|
      next unless member.nil? && role.unassign_blocked_reason

      raise RoleNotUnassignable, role.unassign_blocked_reason
    end

    applied.each do |role, member|
      if role.slug == IncidentRole::SLUG_INCIDENT_LEAD
        assign_lead(incident, member, changed_by: changed_by)
      else
        change_role(incident, role, member, changed_by: changed_by)
      end
    end

    announce_role_changes(incident, applied.reject { |role, _| role.slug == IncidentRole::SLUG_INCIDENT_LEAD })
    applied
  end

  def assign_role(incident, role, member, changed_by:)
    assign_roles(incident, { role => member }, changed_by: changed_by)
  end

  private

  def change_role(incident, role, member, changed_by:)
    if member
      incident.assign_role!(role, member, assigned_by: changed_by.is_a?(WorkspaceMembership) ? changed_by : nil)
    else
      incident.unassign_role!(role)
    end

    incident.incident_events.create!(
      event_type: member ? IncidentEvent::ROLE_ASSIGNED : IncidentEvent::ROLE_UNASSIGNED,
      actor: changed_by,
      metadata: {
        role_id: role.id,
        role_slug: role.slug,
        role_name: role.name,
        member_id: member&.id,
        member_name: member&.actor_display_name
      }.compact
    )
  end

  def announce_role_changes(incident, changes)
    return if changes.empty? || incident.channel_id.blank?

    workspace.adapter.post_role_announcement(
      channel_id: incident.channel_id,
      changes: changes.map { |role, member| { role_name: role.name, platform_user_id: member&.platform_user_id } }
    )
  end
end
