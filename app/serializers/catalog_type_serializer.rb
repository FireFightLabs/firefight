class CatalogTypeSerializer < BaseSerializer
  object_as :catalog_type

  attributes(
    id: { type: :string },
    name: { type: :string },
    slug: { type: :string },
    kind: { type: :string },
    position: { type: :number }
  )

  type :string, optional: true
  def system_key
    catalog_type.system_key
  end

  type :string, optional: true
  def icon
    catalog_type.icon
  end

  type :string, optional: true
  def description
    catalog_type.description
  end

  type :string, optional: true
  def color
    catalog_type.color
  end

  type :number
  def entry_count
    catalog_type.entry_count
  end

  has_many :catalog_attribute_definitions, as: :attribute_definitions, serializer: CatalogAttributeDefinitionSerializer
end
