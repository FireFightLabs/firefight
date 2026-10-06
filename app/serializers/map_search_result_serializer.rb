# One search result for the dashboard's search, with what it is, why it matched and the page that opens it.
class MapSearchResultSerializer < BaseSerializer
  object_as :result

  type "MapSearchType"
  def type = result.type

  type :string
  def id = result.id

  type :string
  def title = result.title

  type :string
  def why = result.why

  type :string
  def href = result.path

  type "ResourceMapKind", optional: true
  def kind = resource&.kind

  type :string, optional: true
  def provider_name = resource && ResourceMap.provider_name(resource.provider)

  type :string, optional: true
  def account = resource&.account

  type :string, optional: true
  def environment = resource&.integration_environment&.environment&.name

  type :string, optional: true
  def catalog_type = result.type == SearchDocument::Search::TYPE_CATALOG_ENTRY ? result.record.catalog_type.name : nil

  # What a memory is about, nil for one about the whole workspace and for anything that is not a memory.
  type :string, optional: true
  def about = result.type == SearchDocument::Search::TYPE_MEMORY ? result.record.about : nil

  private

  def resource = result.type == SearchDocument::Search::TYPE_RESOURCE ? result.record : nil
end
