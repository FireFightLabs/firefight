class IncidentRelationshipService
  def initialize(workspace)
    @workspace = workspace
  end

  def link_related(source:, target:, created_by:)
    return if already_related?(source, target)

    relationship = IncidentRelationship.create!(
      incident: source,
      related_incident: target,
      relationship_type: IncidentRelationship::RELATED,
      created_by: created_by
    )

    record_relationship_event(source, IncidentEvent::RELATIONSHIP_CREATED, created_by, target)
    record_relationship_event(target, IncidentEvent::RELATIONSHIP_CREATED, created_by, source)

    relationship
  end

  # A duplicate is a cancel that names the incident it was a duplicate of.
  # It records MERGED_INTO rather than INCIDENT_CANCELED so the timeline can
  # say which incident absorbed it, and it obeys the same rule every cancel
  # does: a closed incident has to be reopened first.
  def mark_duplicate(source:, canonical:, created_by:)
    canceled_status = @workspace.default_canceled_status
    blocked_reason = source.status_change_blocked_reason(canceled_status)
    raise Incident::NotActive, blocked_reason if blocked_reason

    relationship = IncidentRelationship.create!(
      incident: source,
      related_incident: canonical,
      relationship_type: IncidentRelationship::DUPLICATE,
      created_by: created_by
    )

    source.record_change!(IncidentEvent::MERGED_INTO, by: created_by, metadata: {
      canonical_incident_id: canonical.id,
      canonical_identifier: canonical.identifier
    }) do
      source.update!(incident_status: canceled_status)
    end

    record_relationship_event(canonical, IncidentEvent::MARKED_DUPLICATE, created_by, source)

    if @workspace.archive_channel_enabled && source.channel_id.present?
      ChannelArchivalJob.set(wait: @workspace.archive_channel_delay_minutes.minutes)
        .perform_later(source.id)
    end

    relationship
  end

  private

  def already_related?(source, target)
    IncidentRelationship.related.where(incident_id: source.id, related_incident_id: target.id)
      .or(IncidentRelationship.related.where(incident_id: target.id, related_incident_id: source.id))
      .exists?
  end

  def record_relationship_event(incident, event_type, actor, other_incident)
    incident.incident_events.create!(
      event_type: event_type,
      actor: actor,
      metadata: {
        related_incident_id: other_incident.id,
        related_identifier: other_incident.identifier
      }
    )
  end
end
