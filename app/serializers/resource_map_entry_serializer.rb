# A catalog entry a resource runs for, as the map shows it.
class ResourceMapEntrySerializer < BaseSerializer
  object_as :entry

  type :string
  def id = entry.id

  type :string
  def name = entry.name

  type :string
  def type_name = entry.catalog_type.name

  type :string
  def type_slug = entry.catalog_type.slug
end
