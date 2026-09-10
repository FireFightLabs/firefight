# An overlay row sharing a default's system_field_key overrides it, hidden removes it,
# and a custom row appends a workspace field.
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

  # include_hidden is for the form editor, which must list a hidden field so it can
  # be turned back on. Runtime callers leave it false.
  def fields_for(incident, form_slug)
    resolve(form_slug, context: IncidentConditionEvaluator.context_for(incident))
  end

  def resolve(lifecycle_event, context: {}, include_hidden: false, form: nil)
    raise ArgumentError, "Unknown form slug: #{lifecycle_event}" unless IncidentForm::DEFAULTS_BY_SLUG.key?(lifecycle_event)

    # An IncidentForm row exists only once an admin has customized the form.
    form ||= @workspace.incident_forms.find_by(lifecycle_event: lifecycle_event)
    db_rows = form ? form.incident_form_fields.includes(:incident_conditions, incident_field_definition: [ :incident_field_options, :catalog_type ]).to_a : []

    overrides_by_key = db_rows.select(&:system?).index_by(&:system_field_key)

    merged = IncidentSystemField.defaults_for(lifecycle_event).each_with_index.map do |defn, idx|
      overrides_by_key[defn.key] || default_form_field(lifecycle_event, defn, position: idx)
    end

    # A disabled definition stops being collected without detaching it from the
    # form or touching the values incidents already hold.
    merged += db_rows.select { |row| row.custom? && row.incident_field_definition&.enabled? }

    merged = merged.filter_map { |field| keep(field, lifecycle_event, include_hidden) }
    merged.sort_by!(&:position)

    # An unanswered condition does not match, which keeps a conditional field
    # off the first render of the Declare modal.
    return merged if include_hidden

    # A locked field is asked on every incident, so a condition can never remove
    # it. Writing one is refused, and older ones are ignored here.
    merged.select do |field|
      next false if moot_for_context?(field, context)

      field.locked_visible? || IncidentConditionEvaluator.match?(field.incident_conditions, context)
    end
  end

  # Kept for callers that still bust the cache. The resolver no longer caches.
  def self.bust_cache(_form)
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

    {
      system_attrs: system_attrs,
      custom_fields: custom_fields,
      errors: errors,
      # Lets a caller tell "blanked on the form" from "never asked".
      visible_system_keys: visible_fields.select(&:system?).map(&:system_field_key).to_set
    }
  end

  def validate_submission!(lifecycle_event, raw_params, context: {})
    result = validate_submission(lifecycle_event, raw_params, context: context)
    raise ValidationError.new(result[:errors]) if result[:errors].any?

    result
  end

  # For entry points that carry system attributes as dedicated params, such as
  # the REST API.
  def validate_custom_fields!(lifecycle_event, raw_fields, context: {})
    fields = raw_fields.transform_keys(&:to_s)
    errors = []
    custom_fields = {}

    definitions = resolve(lifecycle_event, context: context)
      .reject(&:system?)
      .index_by { |form_field| form_field.incident_field_definition.slug }

    definitions.each do |slug, form_field|
      value = fields[slug]
      validate_required!(form_field, slug, value, errors)
      validate_custom_value!(form_field.incident_field_definition, value, errors) if value.present?
      custom_fields[slug] = value if value.present?
    end

    unknown = fields.keys - definitions.keys
    errors << "Unknown fields: #{unknown.join(', ')}" if unknown.any?
    raise ValidationError.new(errors) if errors.any?

    custom_fields
  end

  private

  def hidden?(form_field)
    form_field.visibility_mode == IncidentFormField::VISIBILITY_MODE_HIDDEN
  end

  # Hidden means an admin turned it off. Unanswerable means it is configured
  # but has nothing to ask, which the editor still shows so the setup explains itself.
  def keep(field, lifecycle_event, include_hidden)
    return nil if hidden?(field) && !include_hidden

    reason = unanswerable_reason(field, lifecycle_event)
    return field if reason.nil?
    return nil unless include_hidden

    field.inactive_reason = reason
    field
  end

  # Unlike unanswerable_reason, which is about configuration, this changes
  # with each submission and never reaches the editor.
  def moot_for_context?(field, context)
    return false unless field.system?

    case field.system_field_key
    when IncidentSystemField::KEY_NEXT_UPDATE then ending_incident?(context)
    else false
    end
  end

  # Incident::Lifecycle clears next_update_at for a terminal stage, so asking
  # for a time that is then discarded reads as a bug to the responder.
  def ending_incident?(context)
    return false if context[:status].blank?

    terminal_status_ids.include?(context[:status])
  end

  def terminal_status_ids
    @terminal_status_ids ||= @workspace.incident_statuses.terminal.pluck(:id).to_set
  end

  # Lives here rather than in the Slack block builders because validate_submission reads
  # the same set, and a field suppressed only at render would still be demanded on submit.
  def unanswerable_reason(field, lifecycle_event)
    if field.system?
      case field.system_field_key
      when IncidentSystemField::KEY_STATUS then single_status_reason(lifecycle_event)
      when IncidentSystemField::KEY_INCIDENT_TYPE then no_incident_types_reason
      end
    else
      no_options_reason(field.incident_field_definition)
    end
  end

  # The transition already sets the status. Asking adds a step that can only be
  # answered one way.
  def single_status_reason(lifecycle_event)
    stage = TERMINAL_STAGE_BY_FORM[lifecycle_event]
    return nil if stage.nil? || statuses_in_stage(stage) >= 2

    "Responders are not asked this while there is only one #{stage} status, since there is nothing to choose."
  end

  def no_incident_types_reason
    return nil if incident_types?

    "Responders are not asked this until the workspace has at least one incident type."
  end

  def no_options_reason(definition)
    return nil unless definition.selectable?
    return nil if selectable_any?(definition)

    "Responders are not asked this until #{definition.name} has at least one option."
  end

  # Fixed options ride along on the preload. Catalog-backed fields are answered
  # from one query for the whole form rather than an existence check per field.
  def selectable_any?(definition)
    case definition.storage_kind
    when IncidentFieldDefinition::STORAGE_OPTION
      definition.incident_field_options.any?(&:enabled?)
    when IncidentFieldDefinition::STORAGE_CATALOG_ENTRY
      definition.catalog_type_id.present? && stocked_catalog_type_ids.include?(definition.catalog_type_id)
    else
      false
    end
  end

  def stocked_catalog_type_ids
    @stocked_catalog_type_ids ||= @workspace.catalog_entries.active.distinct.pluck(:catalog_type_id).to_set
  end

  def statuses_in_stage(stage)
    @statuses_in_stage ||= {}
    @statuses_in_stage[stage] ||= @workspace.incident_statuses.active.in_stage(stage).count
  end

  def incident_types?
    return @incident_types if defined?(@incident_types)

    @incident_types = @workspace.incident_types.active.exists?
  end

  def default_form_field(lifecycle_event, defn, position:)
    IncidentFormField.new(defn.default_overlay_for(lifecycle_event).merge(position: position))
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

  # A select and a catalog reference differ only in where the allowed set comes
  # from, which selectable_values answers.
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
