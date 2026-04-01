class CatalogTypeOptionSerializer < BaseSerializer
  object_as :catalog_type

  attributes(
    id: { type: :string },
    name: { type: :string },
    slug: { type: :string }
  )

  type :string, optional: true
  def color
    catalog_type.color
  end

  type :string, optional: true
  def icon
    catalog_type.icon
  end
end
