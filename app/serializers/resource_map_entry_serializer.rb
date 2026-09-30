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

  type :string, optional: true
  def purpose = entry.purpose

  # The teams that own it in the catalog, by name.
  type "string[]"
  def owners = entry.owning_teams.map(&:name)
end
