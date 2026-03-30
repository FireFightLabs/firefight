class IncidentRoleSerializer < BaseSerializer
  object_as :role

  type :string
  def id
    role.id
  end

  attributes(
    name: { type: :string },
    slug: { type: :string },
    description: { type: :string, optional: true },
    position: { type: :number }
  )

  type :boolean
  def enabled
    role.deleted_at.nil?
  end

  type :boolean
  def deletable
    role.slug != IncidentRole::SLUG_INCIDENT_LEAD && !role.incident_role_assignments.exists?
  end

  type :boolean
  def system
    role.slug == IncidentRole::SLUG_INCIDENT_LEAD
  end
end
