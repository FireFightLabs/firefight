# An open incident on a catalog service a resource runs for.
class ResourceMapIncidentSerializer < BaseSerializer
  object_as :incident

  type :string
  def id = incident.id

  type :string
  def identifier = incident.identifier

  type :string
  def name = incident.name
end
