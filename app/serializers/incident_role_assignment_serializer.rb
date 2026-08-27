# One incident role and whoever holds it. Every configured role is serialized,
# held or not, so the panel can offer an empty one rather than hiding it.
class IncidentRoleAssignmentSerializer < BaseSerializer
  object_as :seat

  type :string
  def id
    seat.incident_role.id
  end

  type :string
  def name
    seat.incident_role.name
  end

  type :string
  def slug
    seat.incident_role.slug
  end

  type :string, optional: true
  def member_id
    seat.workspace_membership&.id
  end

  has_one :workspace_membership, as: :member, serializer: ActorCompactSerializer, optional: true do
    seat.workspace_membership
  end
end
