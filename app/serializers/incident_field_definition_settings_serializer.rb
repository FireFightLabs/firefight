class IncidentFieldDefinitionSettingsSerializer < BaseSerializer
  object_as :field_definition

  attributes(
    id: { type: :string },
    key: { type: :string },
    name: { type: :string },
    field_type: { type: :string },
    option_source: { type: :string },
    position: { type: :number }
  )

  type :string, optional: true
  def description
    field_definition.description
  end

  type "string[]"
  def options
    field_definition.options
  end

  type :string, optional: true
  def catalog_type_id
    field_definition.catalog_type_id
  end

  type :string, optional: true
  def catalog_type_name
    field_definition.catalog_type&.name
  end

  type :number
  def usage_count
    field_definition.incident_form_fields.count
  end
end
