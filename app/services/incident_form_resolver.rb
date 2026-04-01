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

  def resolve(lifecycle_event)
    form = @workspace.incident_forms.find_by!(lifecycle_event: lifecycle_event)
    field_ids = cached_field_ids(form)

    IncidentFormField
      .includes(:incident_field_definition)
      .where(id: field_ids)
      .order(:position)
  end

  def self.cache_key(form)
    "incident_form/#{form.workspace_id}/#{form.lifecycle_event}"
  end

  def self.bust_cache(form)
    Rails.cache.delete(cache_key(form))
  end

  def validate_submission(lifecycle_event, raw_params)
    visible_fields = resolve(lifecycle_event)
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

  def validate_submission!(lifecycle_event, raw_params)
    result = validate_submission(lifecycle_event, raw_params)
    raise ValidationError.new(result[:errors]) if result[:errors].any?

    result
  end

  private

  def cached_field_ids(form)
    Rails.cache.fetch(self.class.cache_key(form)) do
      form.incident_form_fields
        .where(visibility_mode: IncidentFormField::VISIBILITY_MODE_VISIBLE)
        .order(:position)
        .pluck(:id)
    end
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
