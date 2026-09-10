class IncidentFormFieldSettingsSerializer < BaseSerializer
  object_as :form_field

  attributes(
    field_source_kind: { type: :string },
    position: { type: :number },
    visibility_mode: { type: :string },
    required_mode: { type: :string }
  )

  # Unpersisted default fields get a synthetic `default:<key>` id so the frontend can key and detect them.
  type :string
  def id
    form_field.id || "#{IncidentFormField::SYNTHETIC_PREFIX}#{form_field.system_field_key}"
  end

  type :boolean
  def is_default
    form_field.id.nil?
  end

  type :string, optional: true
  def system_field_key
    form_field.system_field_key
  end

  type :string, optional: true
  def incident_field_definition_id
    form_field.incident_field_definition_id
  end

  type :string
  def name
    source_definition.name
  end

  # Rendered verbatim so the editor preview matches the Slack modal.
  type :string
  def label
    form_field.system? ? source_definition.label : source_definition.name
  end

  type :string, optional: true
  def hint
    form_field.system? ? source_definition.hint : source_definition.description
  end

  type :string, optional: true
  def placeholder
    form_field.system? ? source_definition.placeholder : nil
  end

  type :string, optional: true
  def inactive_reason
    form_field.inactive_reason
  end

  # System fields are keyed by the code registry. Only workspace fields have a slug column.
  type :string
  def slug
    form_field.system? ? form_field.system_field_key : source_definition.slug
  end

  type :string
  def field_type
    source_definition.field_type
  end

  # The model classifies field types, so the editor keeps no list of which are selects.
  type :boolean
  def selectable
    IncidentFieldDefinition.selectable?(source_definition.field_type)
  end

  # A system field is a code Definition, so the option attributes below have no meaning for one.
  type :string, optional: true
  def option_source
    form_field.system? ? IncidentFieldDefinition::OPTION_SOURCE_NONE : source_definition.option_source
  end

  # Filtered in Ruby so the settings preload survives. Catalog-backed fields stay empty,
  # the editor names the catalog type instead.
  type "{ id: string; name: string }[]", optional: true
  def options
    return [] if form_field.system?
    return [] unless source_definition.fixed_options?

    source_definition.selectable_values.map { |id, label| { id: id, name: label } }
  end

  type :string, optional: true
  def catalog_type_id
    form_field.system? ? nil : source_definition.catalog_type_id
  end

  type :string, optional: true
  def catalog_type_name
    form_field.system? ? nil : source_definition.catalog_type&.name
  end

  type :boolean
  def locked_visible
    form_field.locked_visible?
  end

  type :boolean
  def locked_required
    form_field.locked_required?
  end

  type "IncidentConditionSettings[]", optional: true
  def conditions
    form_field.incident_conditions.map do |c|
      { id: c.id, conditionField: c.condition_field, operator: c.operator, values: c.values,
        incidentFieldDefinitionId: c.incident_field_definition_id }
    end
  end

  private

  def source_definition
    if form_field.system?
      IncidentSystemField.fetch(form_field.system_field_key)
    else
      form_field.incident_field_definition
    end
  end
end
