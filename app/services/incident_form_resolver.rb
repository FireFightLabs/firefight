# Resolves the effective field list for an incident form by merging
# code-defined system field defaults with per-workspace DB overlay rows.
#
# Source of truth:
#   - Defaults come from `IncidentSystemField.defaults_for(form_slug)`,
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
  # `form:` is for callers that already hold the row, so resolving does not go
  # and fetch the record it was called on.
  def resolve(lifecycle_event, context: {}, include_hidden: false, form: nil)
    raise ArgumentError, "Unknown form slug: #{lifecycle_event}" unless IncidentForm::DEFAULTS_BY_SLUG.key?(lifecycle_event)

    # IncidentForm rows are optional, they exist only when an admin has
    # customized the form. Fall back to code defaults when no row exists.
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

    # The editor lists every field that can apply, conditions included, because
    # that is the configuration. Responders get the ones that apply right now.
    #
    # Skipping this when the context happened to be empty is what made a
    # conditional field show on the first render of the Declare modal, before
    # anything had been chosen for its condition to read. An unanswered
    # condition does not match, so its field stays hidden until it does.
    return merged if include_hidden

    # A locked field is asked for on every incident, so a condition can never
    # take it away. Writing one is refused, and any that predate that rule are
    # ignored here rather than left able to break declaring.
    merged.select do |field|
      next false if moot_for_context?(field, context)

      field.locked_visible? || IncidentConditionEvaluator.match?(field.incident_conditions, context)
    end
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

  # Decides one field's fate. Hidden means an admin turned it off. Unanswerable
  # means it is configured but has nothing to ask, which the editor still shows
  # so the configuration explains itself.
  def keep(field, lifecycle_event, include_hidden)
    return nil if hidden?(field) && !include_hidden

    reason = unanswerable_reason(field, lifecycle_event)
    return field if reason.nil?
    return nil unless include_hidden

    field.inactive_reason = reason
    field
  end

  # A field the answers so far have made pointless. Distinct from
  # `unanswerable_reason`, which is about how the workspace is configured and
  # so belongs in the editor. This reads what the responder has just picked and
  # changes from one submission to the next, which is why it sits with the
  # condition match and never reaches the editor.
  def moot_for_context?(field, context)
    return false unless field.system?

    case field.system_field_key
    when IncidentSystemField::KEY_NEXT_UPDATE then ending_incident?(context)
    else false
    end
  end

  # An incident being closed or canceled is not waiting on anything, and
  # Incident::Lifecycle clears next_update_at for a terminal stage regardless.
  # Asking for a time that is then discarded reads as a bug to the responder
  # who picked it.
  def ending_incident?(context)
    return false if context[:status].blank?

    terminal_status_ids.include?(context[:status])
  end

  def terminal_status_ids
    @terminal_status_ids ||= @workspace.incident_statuses.terminal.pluck(:id).to_set
  end

  # Why a configured field cannot be put to a responder, or nil if it can.
  #
  # This has to live here rather than in the Slack block builders, because
  # `validate_submission` reads the same resolved set, a field suppressed only
  # at render is still demanded on submit, which produces a modal that can
  # never be submitted and names a field it never showed.
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
    @statuses_in_stage[stage] ||= @workspace.incident_statuses.active.joins(:incident_lifecycle_stage)
      .where(incident_lifecycle_stages: { key: stage }).count
  end

  def incident_types?
    return @incident_types if defined?(@incident_types)

    @incident_types = @workspace.incident_types.active.exists?
  end

  def default_form_field(lifecycle_event, defn, position:)
    mode = defn.required_mode_for(lifecycle_event)

    # An available field ships hidden rather than missing, so the editor can
    # offer it while responders do not see it until someone turns it on.
    available = mode == IncidentFormField::REQUIRED_MODE_AVAILABLE

    IncidentFormField.new(
      field_source_kind: IncidentFormField::FIELD_SOURCE_KIND_SYSTEM,
      system_field_key: defn.key,
      required_mode: available ? IncidentFormField::REQUIRED_MODE_OPTIONAL : mode,
      visibility_mode: available ? IncidentFormField::VISIBILITY_MODE_HIDDEN : IncidentFormField::VISIBILITY_MODE_VISIBLE,
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
