# A role the handbook can name as the one Halon takes direction from in an incident.
class HandbookRoleSerializer < BaseSerializer
  object_as :role

  type :string
  def id = role.id

  type :string
  def name = role.name

  type :string, optional: true
  def description = role.description
end
