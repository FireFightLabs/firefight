class CatalogAttributeDefinitionSerializer < BaseSerializer
  object_as :attr_def

  attributes(
    id: { type: :string },
    slug: { type: :string },
    name: { type: :string },
    required: { type: :boolean },
    position: { type: :number }
  )

  ATTRIBUTE_TYPE_UNION = CatalogAttributeDefinition::ATTRIBUTE_TYPES.map(&:inspect).join(" | ")

  type ATTRIBUTE_TYPE_UNION
  def attribute_type
    attr_def.attribute_type
  end

  type :string, optional: true
  def reference_type_id
    attr_def.config["reference_type_id"]
  end

  type "string[]", optional: true
  def options
    attr_def.config["options"]
  end
end
