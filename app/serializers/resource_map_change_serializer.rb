# Something a sweep saw change on a resource.
class ResourceMapChangeSerializer < BaseSerializer
  object_as :change

  type :string
  def id = change.id

  type :string
  def resource_id = change.resource_id

  type :string
  def resource_name = change.resource.name

  type "ResourceMapChangeKind"
  def kind = change.kind

  type :string, optional: true
  def from_value = change.from_value

  type :string, optional: true
  def to_value = change.to_value

  # Which setting moved, for a configured change.
  type :string, optional: true
  def detail = change.detail

  type :string
  def happened_at = change.happened_at.utc.iso8601
end
