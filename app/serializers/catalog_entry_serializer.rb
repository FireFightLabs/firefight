class CatalogEntrySerializer < BaseSerializer
  object_as :entry

  attributes(
    id: { type: :string },
    name: { type: :string },
    slug: { type: :string }
  )

  type :string
  def type_id
    entry.catalog_type_id
  end

  type "Record<string, unknown>"
  def attributes
    scalar_attrs = entry.entry_attributes.dup

    if entry.outgoing_relationships.loaded?
      entry.outgoing_relationships.each do |rel|
        scalar_attrs[rel.relationship_key] = rel.target_entry_id
      end
    end

    scalar_attrs
  end

  type :string, optional: true
  def source
    entry.source
  end

  type :string, optional: true
  def external_id
    entry.external_id
  end

  type :string
  def created_at
    entry.created_at.utc.iso8601
  end

  type :string
  def updated_at
    entry.updated_at.utc.iso8601
  end
end
