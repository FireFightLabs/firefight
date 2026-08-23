class IncidentRoleAssignmentSerializer < BaseSerializer
  object_as :assignment

  type :string
  def id
    assignment.incident_role_id
  end

  type :string
  def name
    assignment.incident_role.name
  end

  type :string
  def slug
    assignment.incident_role.slug
  end

  has_one :workspace_membership, as: :member, serializer: ActorCompactSerializer
end
