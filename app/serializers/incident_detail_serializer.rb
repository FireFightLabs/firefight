class IncidentDetailSerializer < BaseSerializer
  object_as :incident

  attributes(
    id: { type: :string },
    identifier: { type: :string },
    name: { type: :string },
    summary: { type: :string },
    source: { type: :string },
    channel_name: { type: :string, optional: true },
    channel_id: { type: :string, optional: true },
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
    member = incident.incident_role_assignments.detect { |a| a.incident_role.slug == IncidentRole::SLUG_INCIDENT_LEAD }&.workspace_membership
    return nil unless member

    IncidentLeadSerializer.one(member)
  end

  # The lead has its own field, so this covers the rest of the roster.
  type "IncidentRoleAssignment[]"
  def roles
    incident.incident_role_assignments
      .reject { |assignment| assignment.incident_role.slug == IncidentRole::SLUG_INCIDENT_LEAD }
      .sort_by { |assignment| assignment.incident_role.position }
      .map { |assignment| IncidentRoleAssignmentSerializer.one(assignment) }
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

  type "Record<string, unknown>", optional: true
  def custom_fields
    fields = incident.custom_fields
    fields.presence
  end

  has_many :alerts, serializer: IncidentAlertSerializer

  def alerts
    incident.alerts.includes(:alert_source).order(:received_at)
  end
end
