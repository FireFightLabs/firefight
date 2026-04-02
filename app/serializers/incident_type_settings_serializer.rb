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

  type :number
  def incident_count
    incident_type.incidents.where(deleted_at: nil).count
  end
end
