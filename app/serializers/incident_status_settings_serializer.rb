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
    status.deleted_at.nil?
  end

  type :boolean
  def deletable
    !status.incidents.exists?
  end
end
