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
    status.incident_count
  end

  type :boolean
  def deletable
    status.deletable?
  end

  type :boolean
  def last_enabled_in_stage
    status.last_enabled_in_stage?
  end

  type :boolean
  def defaultable
    status.defaultable?
  end
end
