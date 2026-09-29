# How two resources depend on each other, and how that was found.
class ResourceMapLinkSerializer < BaseSerializer
  object_as :link

  type :string
  def id = link.id

  type :string
  def from_id = link.from_resource_id

  type :string
  def to_id = link.to_resource_id

  type "ResourceMapRelation"
  def relation = link.relation

  type "ResourceMapOrigin"
  def origin = link.origin

  # The connection that declared or matched it, such as Northflank.
  type :string, optional: true
  def found_by = link.integration_environment&.integration&.name

  type :string, optional: true
  def note = link.note

  type :boolean
  def unconfirmed = link.unconfirmed?

  type :string, optional: true
  def removal_blocked_reason = link.removal_blocked_reason
end
