# What a catalog entry is found by: its name and slug, what it is for, its other written attributes and who owns it. What
# it is for is also embedded, so a search by meaning finds the checkout service when asked about payments.
module CatalogEntry::Searchable
  extend ActiveSupport::Concern
  include SearchDocument::Indexing
  include SearchEmbedding::Writing

  FIELD_NAME = "name".freeze
  FIELD_SLUG = "slug".freeze
  FIELD_DESCRIPTION = "description".freeze
  FIELD_ATTRIBUTES = "attributes".freeze
  FIELD_OWNERS = "owners".freeze
  FIELD_TYPE = "type".freeze
  WRITTEN_TYPES = [ CatalogAttributeDefinition::TYPE_TEXT, CatalogAttributeDefinition::TYPE_SELECT, CatalogAttributeDefinition::TYPE_LIST ].freeze

  included do
    after_commit :index_search_document, on: [ :create, :update ]
  end

  class_methods do
    def for_search_documents
      includes(catalog_type: :catalog_attribute_definitions, outgoing_relationships: { target_entry: :catalog_type })
    end

    def search_document_candidates = active
  end

  def search_document_indexable? = deleted_at.nil?

  def search_document_names = [ name, slug ]

  def search_document_fields
    [
      search_document_field(FIELD_NAME, name, "A"),
      search_document_field(FIELD_SLUG, slug, "A"),
      search_document_field(FIELD_DESCRIPTION, purpose, "B"),
      search_document_field(FIELD_ATTRIBUTES, written_attributes, "B"),
      search_document_field(FIELD_OWNERS, owning_teams.map(&:name), "B"),
      search_document_field(FIELD_TYPE, catalog_type.name, "C")
    ]
  end

  def search_document_facets = { catalog_type: catalog_type.name, catalog_type_slug: catalog_type.slug }

  def search_embeddable? = deleted_at.nil? && purpose.present?

  def search_text = [ "#{name} (#{catalog_type.name})", purpose, written_attributes.join(". ") ].compact_blank.join("\n")

  def search_facts = { id: id, name: name, slug: slug, type: catalog_type.name, description: purpose }.compact

  private

  # What people wrote on it besides what it is for, which purpose already holds.
  def written_attributes
    definitions = catalog_type.catalog_attribute_definitions.select { |definition| WRITTEN_TYPES.include?(definition.attribute_type) }
    definitions.reject { |definition| definition.slug == CatalogAttributeDefinition::SLUG_DESCRIPTION }
               .flat_map { |definition| Array(entry_attributes[definition.slug]) }.map(&:to_s).compact_blank
  end

  # Its own row at once. The resources it runs on read its name and its owners, and a rename or an archive also reaches
  # every row that still holds the old name, such as a service it owned or a resource in the environment it is. Those can
  # be many, so they are indexed after.
  def index_search_document
    SearchDocument.index!(CatalogEntry, [ id ])
    SearchDocument.index_later(ResourceMap::Resource, ResourceMap::EntryLink.where(catalog_entry_id: id).pluck(:resource_id))
    return if previously_new_record? || !(saved_change_to_name? || saved_change_to_deleted_at?)

    SearchDocument.naming(workspace_id, name_before_last_save).where.not(searchable_id: id)
                  .pluck(:searchable_type, :searchable_id).group_by(&:first)
                  .each { |type, rows| SearchDocument.index_later(SearchDocument.class_for(type), rows.map(&:last)) }
  end
end
