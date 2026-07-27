class IncidentStatusSettingsSerializer < BaseSerializer
  object_as :status

  type :string
  def id
    status.id
  end

  attributes(
    name: { type: :string },
    slug: { type: :string },
    description: { type: :string, optional: true },
    color: { type: :string },
    position: { type: :number },
    is_default: { type: :boolean }
  )

  type :boolean
  def enabled
    status.enabled?
  end

  type :number
  def incident_count
    status.usage_count
  end

  type :string, optional: true
  def deletion_blocked_reason
    status.deletion_blocked_reason
  end

  type :string, optional: true
  def disable_blocked_reason
    status.disable_blocked_reason
  end

  type :string, optional: true
  def default_blocked_reason
    status.default_blocked_reason
  end
end
