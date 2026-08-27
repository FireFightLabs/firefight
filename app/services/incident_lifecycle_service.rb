class IncidentLifecycleService
  class RoleNotUnassignable < StandardError; end

  ESCALATION_ACK_WAIT = 10.minutes

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

  # Every status change enters here. Which verb runs is decided once, from
  # the stage the incident is in and the stage it is going to, so the API,
  # the update modal and the close, cancel and reopen commands can no longer
  # disagree about what a transition means. The verbs below are private.
  #
  # attrs may carry the usual incident columns plus :lead. Absent a status,
  # the change is a plain update.
  def change_status(incident, attrs, changed_by:, message: nil)
    new_status = attrs[:incident_status] || incident.incident_status
    blocked_reason = incident.status_change_blocked_reason(new_status)
    raise Incident::NotActive, blocked_reason if blocked_reason

    case transition_for(incident, new_status)
    when :close  then close(incident, attrs, changed_by: changed_by)
    when :cancel then cancel(incident, attrs, changed_by: changed_by, message: message)
    when :reopen then reopen(incident, attrs, changed_by: changed_by, reason: message)
    when :accept then accept(incident, attrs, changed_by: changed_by)
    else update(incident, attrs, changed_by: changed_by, message: message)
    end
  end

  # A cancel with no status picked lands on the workspace's first enabled
  # canceled status.
  def cancel_with_default_status(incident, attrs = {}, changed_by:, message: nil)
    change_status(incident, attrs.merge(incident_status: workspace.default_canceled_status),
                  changed_by: changed_by, message: message)
  end

  def assign_lead(incident, lead, changed_by:)
    incident.record_change!(IncidentEvent::LEAD_ASSIGNED, by: changed_by) do
      incident.lead = lead
    end

    LeadAssignmentWorkflow.start!(incident, context: {
      lead_platform_user_id: lead&.platform_user_id
    })
  end

  # Escalation writes an event, asks someone to pick the incident up, and
  # schedules a chase if they do not. The guard lives here rather than on the
  # event, so every entry point inherits it instead of remembering it.
  #
  # `escalated_to` is a member, or the platform id of someone the platform
  # knows. Both are legitimate, since escalating to a person is not what makes
  # them a member. The event carries who and why, so the workflow and the chase
  # need nothing but its id.
  def escalate(incident, escalated_to:, reason:, changed_by:)
    blocked_reason = incident.escalation_blocked_reason
    raise Incident::NotActive, blocked_reason if blocked_reason

    event = incident.incident_events.create!(
      event_type: IncidentEvent::INCIDENT_ESCALATED,
      actor: changed_by,
      metadata: escalation_target(escalated_to).to_metadata.merge(reason: reason)
    )

    IncidentEscalationWorkflow.start!(incident, context: { escalation_event_id: event.id })
    EscalationAcknowledgementReminderJob.set(wait: ESCALATION_ACK_WAIT).perform_later(incident.id, event.id)

    event
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

  def transition_for(incident, new_status)
    from = incident.incident_status.incident_lifecycle_stage
    to = new_status.incident_lifecycle_stage
    return :update if from.id == to.id

    if to.closed? then :close
    elsif to.canceled? then :cancel
    elsif from.closed? || from.canceled? then :reopen
    elsif from.triage? && to.active? then :accept
    else :update
    end
  end

  def update(incident, attrs, changed_by:, message: nil)
    previous_status_name = incident.incident_status.name
    previous_severity_name = incident.incident_severity.name
    previous_type_name = incident.incident_type&.name

    lead = attrs.delete(:lead)
    incident.record_change!(IncidentEvent::INCIDENT_UPDATED, by: changed_by, message: message) do
      incident.update!(attrs)
      incident.lead = lead if lead
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

    # Lead first: the same save closes the incident, and `lead=` refuses once
    # the status has landed. The tracked diff is taken across the whole block,
    # so the order changes nothing about what is recorded.
    incident.record_change!(IncidentEvent::INCIDENT_RESOLVED, by: changed_by) do
      incident.lead = lead if lead
      incident.update!(attrs)
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

    lead = attrs.delete(:lead)
    incident.record_change!(IncidentEvent::INCIDENT_CANCELED, by: changed_by, message: message) do
      incident.lead = lead if lead
      incident.update!(attrs)
    end

    IncidentCancelWorkflow.start!(incident, context: {
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
    lead = attrs.delete(:lead)
    incident.record_change!(
      IncidentEvent::INCIDENT_REOPENED,
      by: changed_by,
      message: reason,
      metadata: reason ? { reason: reason } : nil
    ) do
      incident.update!(attrs)
      incident.lead = lead if lead
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
    lead = attrs.delete(:lead)
    incident.record_change!(IncidentEvent::INCIDENT_ACCEPTED, by: changed_by) do
      incident.update!(attrs)
      incident.lead = lead if lead
      incident.lead = changed_by unless incident.lead
    end

    IncidentUpdateWorkflow.start!(incident, context: {
      updated_by_platform_user_id: changed_by&.platform_user_id
    })
  end

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

  # The timeline names the person, never the platform id. A target who is not
  # yet a member still gets a name and avatar from the platform.
  def escalation_target(person)
    return Incident::EscalationTarget.for_member(person) if person.is_a?(WorkspaceMembership)

    member = @workspace.workspace_memberships.find_by(platform_user_id: person)
    return Incident::EscalationTarget.for_member(member) if member

    info = @workspace.adapter.get_user_info(user_id: person)
    Incident::EscalationTarget.new(
      platform_user_id: person,
      name: info[:real_name].presence || info[:display_name],
      avatar_url: info[:avatar_url]
    )
  rescue AdapterError
    Incident::EscalationTarget.new(platform_user_id: person)
  end

  def announce_role_changes(incident, changes)
    return if changes.empty? || incident.channel_id.blank?

    workspace.adapter.post_role_announcement(
      channel_id: incident.channel_id,
      changes: changes.map { |role, member| { role_name: role.name, platform_user_id: member&.platform_user_id } }
    )
  end
end
