class IncidentFormFieldSettingsSerializer < BaseSerializer
  object_as :form_field

  attributes(
    field_source_kind: { type: :string },
    position: { type: :number },
    visibility_mode: { type: :string },
    required_mode: { type: :string }
  )

  # Persisted overlay rows use their DB id. Unpersisted code-default fields
  # are given a synthetic id (`default:<key>`) so the frontend can key,
  # render, and detect them.
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

  # What a responder reads above and inside the input. The editor renders these
  # verbatim so its preview matches the Slack modal rather than paraphrasing it.
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

  # A system field is a code Definition, not an IncidentFieldDefinition, so the
  # option-related attributes below have no meaning for one.
  type :string, optional: true
  def option_source
    form_field.system? ? IncidentFieldDefinition::OPTION_SOURCE_NONE : source_definition.option_source
  end

  # Sorted in Ruby so the preload survives. Reaching for `.active.ordered` here
  # builds a fresh relation and puts the settings page back to a query per row.
  type "{ id: string; name: string }[]", optional: true
  def options
    return [] if form_field.system?

    source_definition.incident_field_options
      .select(&:enabled?)
      .sort_by { |option| [ option.position, option.created_at ] }
      .map { |option| { id: option.id, name: option.label } }
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
