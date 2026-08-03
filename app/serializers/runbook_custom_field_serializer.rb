class RunbookCustomFieldSerializer < BaseSerializer
  object_as :field_definition

  attributes(
    id: { type: :string },
    key: { type: :string },
    name: { type: :string },
    field_type: { type: :string }
  )

  type "{ id: string; name: string }[]"
  def options
    field_definition.incident_field_options.active.ordered.map { |option| { id: option.id, name: option.label } }
  end

  type :string, optional: true
  def catalog_type_id
    field_definition.catalog_type_id
  end

  type "{ id: string; name: string }[]"
  def entries
    return [] unless field_definition.catalog_options?

    field_definition.workspace.catalog_entries.active
      .where(catalog_type_id: field_definition.catalog_type_id)
      .order(:name)
      .map { |entry| { id: entry.id, name: entry.name } }
  end
end
