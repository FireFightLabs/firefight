class IncidentTypeSettingsSerializer < BaseSerializer
  object_as :incident_type

  type :string
  def id
    incident_type.id
  end

  attributes(
    name: { type: :string },
    slug: { type: :string },
    description: { type: :string, optional: true },
    color: { type: :string, optional: true },
    position: { type: :number },
    is_default: { type: :boolean }
  )

  type :boolean
  def enabled
    incident_type.enabled?
  end

  type :number
  def incident_count
    incident_type.usage_count
  end

  type :string, optional: true
  def deletion_blocked_reason
    incident_type.deletion_blocked_reason
  end

  type :string, optional: true
  def disable_blocked_reason
    incident_type.disable_blocked_reason
  end

  type :string, optional: true
  def default_blocked_reason
    incident_type.default_blocked_reason
  end
end
