# Resolves the effective field list for an incident form by merging
# code-defined system field defaults with per-workspace DB overlay rows.
#
# Source of truth:
#   - Defaults come from `IncidentSystemField.defaults_for(form_slug)` —
#     they always exist, the code depends on them, no migration is needed
#     when a new system field is added.
#   - DB rows in `incident_form_fields` are overlays:
#     * a row with the same `system_field_key` as a default OVERRIDES the
#       default's required_mode / visibility_mode / position / conditions
#       (visibility_mode: hidden removes the field from the resolved set)
#     * a row with `field_source_kind: custom` APPENDS a workspace-defined
#       custom field
#
# `validate_submission` then validates raw params against the resolved set.
class IncidentFormResolver
  class ValidationError < StandardError
    attr_reader :field_errors

    def initialize(field_errors)
      @field_errors = field_errors
      super(field_errors.join("; "))
    end
  end

  def initialize(workspace)
    @workspace = workspace
  end

  def resolve(lifecycle_event, context: {})
    raise ArgumentError, "Unknown form slug: #{lifecycle_event}" unless IncidentForm::DEFAULTS_BY_SLUG.key?(lifecycle_event)

    # IncidentForm rows are optional — they exist only when an admin has
    # customized the form. Fall back to code defaults when no row exists.
    form = @workspace.incident_forms.find_by(lifecycle_event: lifecycle_event)
    db_rows = form ? form.incident_form_fields.includes(:incident_field_definition, :incident_conditions).to_a : []

    overrides_by_key = db_rows
      .select { |r| r.field_source_kind == IncidentFormField::FIELD_SOURCE_KIND_SYSTEM }
      .index_by(&:system_field_key)

    custom_rows = db_rows.select { |r| r.field_source_kind == IncidentFormField::FIELD_SOURCE_KIND_CUSTOM }

    merged = []

    IncidentSystemField.defaults_for(lifecycle_event).each_with_index do |defn, idx|
      override = overrides_by_key[defn.key]
      if override
        next if override.visibility_mode == IncidentFormField::VISIBILITY_MODE_HIDDEN
        merged << override
      else
        merged << default_form_field(lifecycle_event, defn, position: idx)
      end
    end

    custom_rows.each do |row|
      next if row.visibility_mode == IncidentFormField::VISIBILITY_MODE_HIDDEN
      # A disabled definition stops being collected without detaching it from
      # the form or touching the values incidents already hold.
      next unless row.incident_field_definition&.enabled?

      merged << row
    end

    merged.sort_by!(&:position)

    return merged if context.empty?

    merged.select { |field| IncidentConditionEvaluator.match?(field.incident_conditions, context) }
  end

  # Kept for backwards compatibility with callers that still bust the cache
  # after mutating form fields. The resolver no longer caches (queries are
  # small and per-modal-open), but the no-op keeps the API stable.
  def self.bust_cache(_form)
    # no-op
  end

  def validate_submission(lifecycle_event, raw_params, context: {})
    visible_fields = resolve(lifecycle_event, context: context)
    system_attrs = {}
    custom_fields = {}
    errors = []

    raw_params = raw_params.transform_keys(&:to_s)

    visible_fields.each do |form_field|
      if form_field.field_source_kind == IncidentFormField::FIELD_SOURCE_KIND_SYSTEM
        key = form_field.system_field_key
        value = raw_params[key]
        validate_required!(form_field, key, value, errors)
        system_attrs[key] = value if value.present?
      else
        defn = form_field.incident_field_definition
        key = defn.key
        value = raw_params[key]
        validate_required!(form_field, key, value, errors)
        validate_custom_value!(defn, value, errors) if value.present?
        custom_fields[key] = value if value.present?
      end
    end

    known_keys = visible_fields.map { |f|
      f.system_field_key || f.incident_field_definition&.key
    }.compact
    unknown = raw_params.keys - known_keys
    errors << "Unknown fields: #{unknown.join(', ')}" if unknown.any?

    { system_attrs: system_attrs, custom_fields: custom_fields, errors: errors }
  end

  def validate_submission!(lifecycle_event, raw_params, context: {})
    result = validate_submission(lifecycle_event, raw_params, context: context)
    raise ValidationError.new(result[:errors]) if result[:errors].any?

    result
  end

  private

  # Builds an unpersisted IncidentFormField that represents a code-default
  # system field. Downstream consumers iterate the same `IncidentFormField`
  # interface whether the field came from defaults or DB. We don't set
  # `incident_form` because the form itself may not be persisted either.
  def default_form_field(lifecycle_event, defn, position:)
    IncidentFormField.new(
      field_source_kind: IncidentFormField::FIELD_SOURCE_KIND_SYSTEM,
      system_field_key: defn.key,
      required_mode: defn.required_mode_for(lifecycle_event),
      visibility_mode: IncidentFormField::VISIBILITY_MODE_VISIBLE,
      position: position
    )
  end

  def validate_required!(form_field, key, value, errors)
    required = form_field.required_mode.in?([
      IncidentFormField::REQUIRED_MODE_REQUIRED,
      IncidentFormField::REQUIRED_MODE_FIXED_REQUIRED
    ])

    if required && value.blank?
      name = form_field.source_name || key
      errors << "#{name} is required"
    end
  end

  def validate_custom_value!(defn, value, errors)
    case defn.field_type
    when IncidentFieldDefinition::TYPE_TEXT, IncidentFieldDefinition::TYPE_LINK
      unless value.is_a?(String)
        errors << "#{defn.name} must be a string"
      end
    when IncidentFieldDefinition::TYPE_NUMBER
      unless value.is_a?(Numeric) || (value.is_a?(String) && value.match?(/\A-?\d+(\.\d+)?\z/))
        errors << "#{defn.name} must be a number"
      end
    when IncidentFieldDefinition::TYPE_SINGLE_SELECT
      validate_single_option!(defn, value, errors)
    when IncidentFieldDefinition::TYPE_MULTI_SELECT
      validate_multi_options!(defn, value, errors)
    when IncidentFieldDefinition::TYPE_CATALOG_REFERENCE
      validate_catalog_ref!(defn, value, errors)
    when IncidentFieldDefinition::TYPE_CATALOG_MULTI_REFERENCE
      validate_catalog_multi_ref!(defn, value, errors)
    end
  end

  def validate_single_option!(defn, value, errors)
    return unless value.is_a?(String)

    if defn.fixed_options?
      unless defn.options.include?(value)
        errors << "#{defn.name} must be one of: #{defn.options.join(', ')}"
      end
    elsif defn.catalog_options?
      validate_catalog_entry!(defn, value, errors)
    end
  end

  def validate_multi_options!(defn, value, errors)
    unless value.is_a?(Array)
      errors << "#{defn.name} must be an array"
      return
    end

    if defn.fixed_options?
      invalid = value - defn.options
      if invalid.any?
        errors << "#{defn.name} contains invalid options: #{invalid.join(', ')}"
      end
    elsif defn.catalog_options?
      value.each { |v| validate_catalog_entry!(defn, v, errors) }
    end
  end

  def validate_catalog_ref!(defn, value, errors)
    unless value.is_a?(String)
      errors << "#{defn.name} must be a string"
      return
    end

    validate_catalog_entry!(defn, value, errors)
  end

  def validate_catalog_multi_ref!(defn, value, errors)
    unless value.is_a?(Array)
      errors << "#{defn.name} must be an array"
      return
    end

    value.each { |v| validate_catalog_entry!(defn, v, errors) }
  end

  def validate_catalog_entry!(defn, entry_id, errors)
    return if entry_id.blank?

    catalog_type_id = defn.catalog_type_id
    return if catalog_type_id.blank?

    unless @workspace.catalog_entries.active.where(catalog_type_id: catalog_type_id, id: entry_id).exists?
      errors << "#{defn.name} references an invalid catalog entry"
    end
  end
end
