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

  has_one :incident_severity, as: :severity, serializer: SeverityCompactSerializer
  has_one :incident_status, as: :status, serializer: StatusCompactSerializer

  # Nested serializer output goes through the association DSL so the
  # generator emits a sibling import. A bare `type :Name` is treated as a
  # hand-written custom type and the import dangles.
  has_one :type, serializer: IncidentTypeCompactSerializer, optional: true do
    incident.incident_type
  end

  has_one :lead, serializer: ActorCompactSerializer, optional: true do
    incident.lead
  end

  # The sentence a blocked control shows instead of vanishing. Nil while the
  # incident can still be changed.
  type :string, optional: true
  def change_blocked_reason
    incident.change_blocked_reason
  end

  # The chip renders a person, the lead picker needs the row it points at.
  # Matching the chip's name back to a member breaks the moment two people
  # share a display name.
  type :string, optional: true
  def lead_id
    incident.lead&.id
  end

  # The lead has its own field, so this covers the rest of the roster. Every
  # configured role appears, whether or not anyone holds it.
  has_many :roles, serializer: IncidentRoleAssignmentSerializer do
    incident.role_roster
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
