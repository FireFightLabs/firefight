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
    incident.lead&.user&.name
  end

  # A name, like `lead`. The table shows text, not chips.
  type :string, optional: true
  def declared_by
    incident.declared_by&.actor_display_name
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
