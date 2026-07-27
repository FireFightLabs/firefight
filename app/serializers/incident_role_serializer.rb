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
    role.enabled?
  end

  type :boolean
  def system
    role.system?
  end

  type :number
  def incident_count
    role.usage_count
  end

  type :string, optional: true
  def deletion_blocked_reason
    role.deletion_blocked_reason
  end

  type :string, optional: true
  def disable_blocked_reason
    role.disable_blocked_reason
  end
end
