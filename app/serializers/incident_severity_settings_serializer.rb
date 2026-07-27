class IncidentSeveritySettingsSerializer < BaseSerializer
  object_as :severity

  type :string
  def id
    severity.id
  end

  attributes(
    name: { type: :string },
    slug: { type: :string },
    description: { type: :string, optional: true },
    color: { type: :string },
    rank: { type: :number },
    position: { type: :number },
    is_default: { type: :boolean }
  )

  type :boolean
  def enabled
    severity.enabled?
  end

  type :number
  def incident_count
    severity.usage_count
  end

  type :string, optional: true
  def deletion_blocked_reason
    severity.deletion_blocked_reason
  end

  type :string, optional: true
  def disable_blocked_reason
    severity.disable_blocked_reason
  end

  type :string, optional: true
  def default_blocked_reason
    severity.default_blocked_reason
  end
end
