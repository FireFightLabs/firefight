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
    severity.deleted_at.nil?
  end

  type :number
  def incident_count
    severity.incident_count
  end

  type :boolean
  def deletable
    severity.deletable?
  end
end
