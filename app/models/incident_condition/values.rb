# Conditions match on ids, but a caller knows slugs. Accept either, and refuse
# anything that resolves to neither. A stored value matching no record produces
# a condition that saves cleanly and then never fires.
module IncidentCondition::Values
  UUID_FORMAT = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/

  # Every attribute a condition row needs, so a caller never has to know that
  # a custom field condition carries a definition alongside its values.
  def self.attributes(workspace, condition)
    definition = resolve_definition(workspace, condition)

    {
      condition_field: condition[:condition_field],
      operator: condition[:operator],
      values: resolve(workspace, condition, definition),
      incident_field_definition_id: definition&.id
    }
  end

  def self.resolve(workspace, condition, definition = nil)
    values = Array(condition[:values]).map(&:to_s)
    return option_ids(definition, values) if definition

    scope = scope_for(workspace, condition[:condition_field])
    return values unless scope

    match(values, scope.pluck(:slug, :id).to_h) do |value, offered|
      "unknown #{condition[:condition_field]} #{value.inspect}. Valid: #{offered.join(', ')}"
    end
  end

  # A custom field condition names its field. The id form stays accepted so a
  # caller already holding one keeps working.
  def self.resolve_definition(workspace, condition)
    return nil unless condition[:condition_field].to_s == IncidentCondition::FIELD_CUSTOM_FIELD

    scope = workspace.incident_field_definitions.active
    reference = (condition[:custom_field] || condition[:incident_field_definition_id]).to_s
    definition = reference.match?(UUID_FORMAT) ? scope.find_by(id: reference) : scope.find_by(slug: reference)
    return definition if definition

    raise ArgumentError,
      "unknown custom field #{reference.inspect}. Valid: #{scope.order(:slug).pluck(:slug).join(', ')}"
  end

  # Which table a stored value comes from is the field's own business, so the
  # accepted keys follow its storage rather than being guessed from the type.
  def self.option_ids(definition, values)
    match(values, offered_keys(definition)) do |value, offered|
      "unknown value #{value.inspect} for #{definition.name}. Valid: #{offered.join(', ')}"
    end
  end

  def self.offered_keys(definition)
    case definition.storage_kind
    when IncidentFieldDefinition::STORAGE_OPTION
      definition.incident_field_options.active.to_h { |option| [ option.label, option.id ] }
    when IncidentFieldDefinition::STORAGE_CATALOG_ENTRY
      definition.workspace.catalog_entries.active
        .where(catalog_type_id: definition.catalog_type_id)
        .to_h { |entry| [ entry.slug, entry.id ] }
    else
      raise ArgumentError,
        "#{definition.name} is a #{definition.field_type} field and cannot carry a condition"
    end
  end

  def self.match(values, by_key)
    known_ids = by_key.values.to_set

    values.map do |value|
      next value if known_ids.include?(value)
      next by_key[value] if by_key.key?(value)

      raise ArgumentError, yield(value, by_key.keys.sort)
    end
  end

  def self.scope_for(workspace, condition_field)
    case condition_field
    when IncidentCondition::FIELD_SEVERITY      then workspace.incident_severities.active
    when IncidentCondition::FIELD_INCIDENT_TYPE then workspace.incident_types.active
    end
  end
end
