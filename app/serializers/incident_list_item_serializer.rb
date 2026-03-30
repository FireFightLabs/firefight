class IncidentListItemSerializer < BaseSerializer
  object_as :incident

  attributes(
    id: { type: :string },
    identifier: { type: :string },
    name: { type: :string }
  )

  has_one :incident_severity, as: :severity, serializer: SeverityCompactSerializer
  has_one :incident_status, as: :status, serializer: StatusCompactSerializer

  type :string, optional: true
  def lead
    assignment = incident.incident_role_assignments.detect { |a| a.incident_role.slug == IncidentRole::SLUG_INCIDENT_LEAD }
    assignment&.workspace_membership&.user&.name
  end

  type :string
  def declared_at
    incident.declared_at.utc.iso8601
  end

  type :string, optional: true
  def resolved_at
    incident.resolved_at&.utc&.iso8601
  end
end
