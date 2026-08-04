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
  TERMINAL_STAGE_BY_FORM = {
    IncidentForm::SLUG_RESOLVE => IncidentLifecycleStage::CLOSED,
    IncidentForm::SLUG_CANCEL => IncidentLifecycleStage::CANCELED
  }.freeze

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

  # include_hidden is for the form editor, which has to show a hidden field to
  # let anyone turn it back on. Every runtime caller leaves it false, so a
  # hidden field never reaches a responder.
  def resolve(lifecycle_event, context: {}, include_hidden: false)
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
        next if hidden?(override) && !include_hidden
        merged << override
      else
        field = default_form_field(lifecycle_event, defn, position: idx)
        merged << field if field
      end
    end

    custom_rows.each do |row|
      next if hidden?(row) && !include_hidden
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
        key = defn.slug
        value = raw_params[key]
        validate_required!(form_field, key, value, errors)
        validate_custom_value!(defn, value, errors) if value.present?
        custom_fields[key] = value if value.present?
      end
    end

    known_keys = visible_fields.map { |f|
      f.system_field_key || f.incident_field_definition&.slug
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
  def hidden?(form_field)
    form_field.visibility_mode == IncidentFormField::VISIBILITY_MODE_HIDDEN
  end

  # Status only earns a place on a terminal form when the stage it moves to
  # holds more than one status. With a single option there is no choice to
  # make, so asking would turn a one-command action into a modal.
  def redundant_status?(lifecycle_event, defn)
    return false unless defn.key == IncidentSystemField::KEY_STATUS

    stage = TERMINAL_STAGE_BY_FORM[lifecycle_event]
    return false if stage.nil?

    @workspace.incident_statuses.active.joins(:incident_lifecycle_stage)
      .where(incident_lifecycle_stages: { key: stage }).count < 2
  end

  def default_form_field(lifecycle_event, defn, position:)
    mode = defn.required_mode_for(lifecycle_event)
    return nil if mode == IncidentFormField::REQUIRED_MODE_AVAILABLE
    return nil if redundant_status?(lifecycle_event, defn)

    IncidentFormField.new(
      field_source_kind: IncidentFormField::FIELD_SOURCE_KIND_SYSTEM,
      system_field_key: defn.key,
      required_mode: mode,
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

  # Cardinality first, then what the entries have to be. A select and a catalog
  # reference differ only in where the allowed set comes from, which the
  # definition answers with selectable_values.
  def validate_custom_value!(defn, value, errors)
    return validate_scalar!(defn, value, errors) unless defn.selectable?

    entries = if defn.multi_valued?
      return errors << "#{defn.name} must be an array" unless value.is_a?(Array)

      value
    else
      return errors << "#{defn.name} must be a string" unless value.is_a?(String)

      [ value ]
    end

    allowed = selectable_values(defn)
    invalid = entries.select(&:present?) - allowed.keys
    return if invalid.empty?

    errors << invalid_selection_message(defn, allowed)
  end

  # A fixed list is short enough to spell out. A catalog type can hold hundreds
  # of entries, so naming them all would be worse than saying nothing.
  def invalid_selection_message(defn, allowed)
    if defn.storage_kind == IncidentFieldDefinition::STORAGE_CATALOG_ENTRY
      "#{defn.name} references an invalid catalog entry"
    else
      "#{defn.name} must be one of: #{allowed.values.join(', ')}"
    end
  end

  def validate_scalar!(defn, value, errors)
    if defn.field_type == IncidentFieldDefinition::TYPE_NUMBER
      unless value.is_a?(Numeric) || (value.is_a?(String) && value.match?(/\A-?\d+(\.\d+)?\z/))
        errors << "#{defn.name} must be a number"
      end
    elsif !value.is_a?(String)
      errors << "#{defn.name} must be a string"
    end
  end

  def selectable_values(defn)
    @selectable_values ||= {}
    @selectable_values[defn.id] ||= defn.selectable_values
  end
end
