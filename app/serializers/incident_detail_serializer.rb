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

  # Nested serializer output goes through the association DSL so the
  # generator emits a sibling import. A bare `type :Name` is treated as a
  # hand-written custom type and the import dangles.
  has_one :type, serializer: IncidentTypeCompactSerializer, optional: true do
    incident.incident_type
  end

  has_one :lead, serializer: ActorCompactSerializer, optional: true do
    incident.lead
  end

  # The lead has its own field, so this covers the rest of the roster.
  has_many :roles, serializer: IncidentRoleAssignmentSerializer do
    incident.incident_role_assignments
      .reject { |assignment| assignment.incident_role.slug == IncidentRole::SLUG_INCIDENT_LEAD }
      .sort_by { |assignment| assignment.incident_role.position }
  end

  has_one :declared_by, serializer: ActorCompactSerializer, optional: true do
    incident.declared_by
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
    incident.custom_fields_for_display.presence
  end

  has_many :alerts, serializer: IncidentAlertSerializer

  def alerts
    incident.alerts.includes(:alert_source).order(:received_at)
  end

  has_many :runbooks, serializer: IncidentRunbookSerializer

  def runbooks
    incident.incident_runbooks.includes(runbook: :runbook_steps).order(:created_at)
  end
end
