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

  type :ActorCompact
  def member
    ActorCompactSerializer.one(assignment.workspace_membership)
  end
end
