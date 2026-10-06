# What a resource on the map is found by: its name and the provider's id, where it runs, what the provider says about it,
# its tags, the catalog services it runs and the teams that own them.
module ResourceMap::Resource::Searchable
  extend ActiveSupport::Concern
  include SearchDocument::Indexing

  FIELD_NAME = "name".freeze
  FIELD_ID = "id".freeze
  FIELD_ACCOUNT = "account".freeze
  FIELD_DETAILS = "details".freeze
  FIELD_TAGS = "tags".freeze
  FIELD_CATALOG = "catalog".freeze
  FIELD_OWNERS = "owners".freeze
  FIELD_KIND = "kind".freeze
  FIELD_PROVIDER = "provider".freeze

  class_methods do
    def for_search_documents
      includes(entry_links: { catalog_entry: [ :catalog_type, { outgoing_relationships: { target_entry: :catalog_type } } ] })
    end

    # The environments of the connection rows that report each resource, in one query for the batch.
    def prepare_search_documents(records)
      ids = records.flat_map(&:reporting_row_ids).uniq
      names = IntegrationEnvironment.where(id: ids).includes(:environment).to_h { |row| [ row.id.to_s, row.environment&.name ] }
      records.each { |record| record.search_environments = names.values_at(*record.reporting_row_ids).compact.uniq.sort }
    end
  end

  attr_writer :search_environments

  def reporting_row_ids = [ integration_environment_id, *sightings.to_h.keys ].compact.map(&:to_s).uniq

  def search_document_names = [ name, external_id, account ]

  def search_document_fields
    [
      search_document_field(FIELD_NAME, name, "A"),
      search_document_field(FIELD_ID, external_id, "A"),
      search_document_field(FIELD_ACCOUNT, account, "B"),
      search_document_field(FIELD_DETAILS, details.except(ResourceMap::TAGS).values.grep(String), "B"),
      search_document_field(FIELD_TAGS, search_tags, "B"),
      search_document_field(FIELD_CATALOG, search_catalog_entries.map(&:name), "B"),
      search_document_field(FIELD_OWNERS, search_owners.map(&:name), "B"),
      search_document_field(FIELD_KIND, [ kind, kind.tr("_", " ") ], "C"),
      search_document_field(FIELD_PROVIDER, [ provider, ResourceMap.provider_name(provider) ], "C")
    ]
  end

  def search_document_facets
    { kind: kind, provider: provider, environments: @search_environments || [] }
  end

  private

  # A tag reads as key=value and is found by either half.
  def search_tags
    details[ResourceMap::TAGS].to_h.flat_map { |key, value| value.nil? ? [ key ] : [ "#{key}=#{value}", key, value ] }
  end

  def search_catalog_entries = entry_links.map(&:catalog_entry).select { |entry| entry.deleted_at.nil? }

  # A team the resource is linked to, or one a linked service names as its owner, as ResourceMap::Query's owner filter reads it.
  def search_owners
    entries = search_catalog_entries
    teams = entries.select { |entry| entry.catalog_type.system_key == CatalogType::SYSTEM_KEY_TEAM }
    (teams + entries.flat_map(&:owning_teams)).uniq
  end
end
