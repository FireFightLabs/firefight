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

  def mark_duplicate(source:, canonical:, created_by:)
    relationship = IncidentRelationship.create!(
      incident: source,
      related_incident: canonical,
      relationship_type: IncidentRelationship::DUPLICATE,
      created_by: created_by
    )

    canceled_status = @workspace.incident_statuses.canceled.first
    source.record_change!(IncidentEvent::MERGED_INTO, changed_by: created_by, details: {
      canonical_incident_id: canonical.id,
      canonical_identifier: canonical.identifier
    }) do
      source.update!(incident_status: canceled_status)
    end

    record_relationship_event(canonical, IncidentEvent::MARKED_DUPLICATE, created_by, source)

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
      user: actor,
      metadata: {
        details: {
          related_incident_id: other_incident.id,
          related_identifier: other_incident.identifier
        }
      }
    )
  end
end
