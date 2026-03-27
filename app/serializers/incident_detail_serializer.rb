class IncidentDetailSerializer < BaseSerializer
  object_as :incident

  attributes(
    id: { type: :string },
    identifier: { type: :string },
    name: { type: :string },
    summary: { type: :string },
    source: { type: :string },
    channel_name: { type: :string, optional: true },
    is_private: { type: :boolean }
  )

  has_one :incident_severity, as: :severity, serializer: SeverityDetailSerializer
  has_one :incident_status, as: :status, serializer: StatusDetailSerializer

  type :IncidentTypeCompact, optional: true
  def type
    return nil unless incident.incident_type

    IncidentTypeCompactSerializer.one(incident.incident_type)
  end

  type :IncidentLead, optional: true
  def lead
    member = incident.incident_role_assignments.detect { |a| a.incident_role.slug == "incident_lead" }&.workspace_membership
    return nil unless member

    IncidentLeadSerializer.one(member)
  end

  type :ActorCompact, optional: true
  def declared_by
    return nil unless incident.declared_by

    ActorCompactSerializer.one(incident.declared_by)
  end

  type :string
  def declared_at
    incident.declared_at.utc.iso8601
  end

  type :string, optional: true
  def detected_at
    incident.detected_at&.utc&.iso8601
  end

  type :string, optional: true
  def resolved_at
    incident.resolved_at&.utc&.iso8601
  end
end
