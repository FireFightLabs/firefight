class IncidentFormFieldSettingsSerializer < BaseSerializer
  object_as :form_field

  attributes(
    field_source_kind: { type: :string },
    position: { type: :number },
    visibility_mode: { type: :string },
    required_mode: { type: :string },
    locked_required: { type: :boolean }
  )

  # Persisted overlay rows use their DB id. Unpersisted code-default fields
  # are given a synthetic id (`default:<key>`) so the frontend can key,
  # render, and detect them.
  type :string
  def id
    form_field.id || "default:#{form_field.system_field_key}"
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

  type :string, optional: true
  def description
    source_definition.description
  end

  # A system field's identifier comes from the code registry, which keys its
  # definitions rather than slugging them. Only workspace-defined fields have a
  # slug column.
  type :string
  def slug
    form_field.system? ? form_field.system_field_key : source_definition.slug
  end

  type :string
  def field_type
    source_definition.field_type
  end

  type :string, optional: true
  def option_source
    source_definition.respond_to?(:option_source) ? source_definition.option_source : IncidentFieldDefinition::OPTION_SOURCE_NONE
  end

  type "{ id: string; name: string }[]", optional: true
  def options
    return [] unless source_definition.is_a?(IncidentFieldDefinition)

    source_definition.incident_field_options.active.ordered.map { |option| { id: option.id, name: option.label } }
  end

  type :string, optional: true
  def catalog_type_id
    source_definition.respond_to?(:catalog_type_id) ? source_definition.catalog_type_id : nil
  end

  type :string, optional: true
  def catalog_type_name
    source_definition.respond_to?(:catalog_type) ? source_definition.catalog_type&.name : nil
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
      { id: c.id, conditionField: c.condition_field, operator: c.operator, values: c.values }
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
