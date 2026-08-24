class RunbookCustomFieldSerializer < BaseSerializer
  object_as :field_definition

  attributes(
    id: { type: :string },
    slug: { type: :string },
    name: { type: :string },
    field_type: { type: :string }
  )

  type "{ id: string; name: string }[]"
  def options
    return [] unless field_definition.fixed_options?

    field_definition.selectable_values.map { |id, label| { id: id, name: label } }
  end

  type :string, optional: true
  def catalog_type_id
    field_definition.catalog_type_id
  end

  type "{ id: string; name: string }[]"
  def entries
    return [] unless field_definition.catalog_options?

    field_definition.selectable_values.map { |id, label| { id: id, name: label } }
  end
end
