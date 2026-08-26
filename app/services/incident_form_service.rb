class IncidentFormService
  def initialize(workspace)
    @workspace = workspace
  end

  def add_custom_field(form, incident_field_definition)
    ActiveRecord::Base.transaction do
      field = form.incident_form_fields.create!(
        field_source_kind: IncidentFormField::FIELD_SOURCE_KIND_CUSTOM,
        incident_field_definition: incident_field_definition,
        position: next_position(form),
        visibility_mode: IncidentFormField::VISIBILITY_MODE_VISIBLE,
        required_mode: IncidentFormField::REQUIRED_MODE_OPTIONAL
      )
      bust_cache(form)
      field
    end
  end

  # A system field has no DB row until an admin changes something about it, so
  # the editor addresses it by `default:<key>` until one exists. Creating it on
  # first edit keeps the code defaults as the single source of truth, a row
  # only ever means "this workspace overrode something".
  def ensure_system_field!(form, system_field_key)
    existing = form.incident_form_fields.find_by(
      field_source_kind: IncidentFormField::FIELD_SOURCE_KIND_SYSTEM,
      system_field_key: system_field_key
    )
    return existing if existing

    overlay = IncidentSystemField.fetch(system_field_key).default_overlay_for(form.lifecycle_event)
    raise ArgumentError, "#{system_field_key} does not appear on the #{form.lifecycle_event} form" if overlay.nil?

    form.incident_form_fields.create!(overlay)
  end

  def update_field(form_field, visibility_mode:, required_mode:)
    ActiveRecord::Base.transaction do
      attrs = {}
      attrs[:visibility_mode] = visibility_mode unless form_field.locked_visible?
      attrs[:required_mode] = required_mode unless form_field.locked_required?
      form_field.update!(attrs)
      bust_cache(form_field.incident_form)
      form_field
    end
  end

  def remove_field(form_field)
    if form_field.system?
      raise ActiveRecord::RecordNotDestroyed, "System form fields cannot be removed"
    end

    ActiveRecord::Base.transaction do
      form = form_field.incident_form
      form_field.destroy!
      normalize_positions!(form)
      bust_cache(form)
    end
  end

  def move_up(form_field)
    move(form_field, -1)
  end

  def move_down(form_field)
    move(form_field, 1)
  end

  # A system field the workspace has never customized has no row to carry a
  # position, so the editor addresses it by `default:<key>` and dragging it
  # materializes one, the same way editing it does. Skipping those ids instead
  # meant reordering a form made only of code defaults saved nothing while
  # still reporting success.
  def reorder(form, ordered_ids)
    ActiveRecord::Base.transaction do
      Array(ordered_ids).each_with_index do |id, index|
        field = field_for_reorder(form, id.to_s)
        field.update!(position: index + 1) unless field.position == index + 1
      end
      bust_cache(form)
    end
  end

  # Changing what one lifecycle form asks for, from the shape every surface
  # hands in. A system field has no row until something about it is changed and
  # a custom field has none until it is attached, so both are materialized here
  # rather than making a caller create one first.
  def upsert_field!(args)
    form = @workspace.ensure_incident_form!(form_slug(args))
    form_field = resolve_field(form, args)

    update_field(
      form_field,
      visibility_mode: visibility_mode(args, form_field),
      required_mode: required_mode(args, form_field)
    )
    form_field.sync_conditions!(condition_params(args)) if args.key?(:conditions)

    [ form, form_field.reload ]
  end

  private

  def form_slug(args)
    slug = args[:form].to_s
    raise ArgumentError, "unknown form #{slug.inspect}. Valid: #{IncidentForm::SLUGS.join(', ')}" unless IncidentForm::SLUGS.include?(slug)

    slug
  end

  # A system field has no row until something about it is changed, and a
  # custom field has none until it is attached, so both are materialized
  # here rather than making the agent create one first.
  def resolve_field(form, args)
    if args[:system_field].present?
      ensure_system_field!(form, args[:system_field].to_s)
    elsif args[:custom_field].present?
      definition = form.workspace.incident_field_definitions.active.find_by(slug: args[:custom_field].to_s)
      raise ArgumentError, "unknown custom field #{args[:custom_field].to_s.inspect}" if definition.nil?

      existing = form.incident_form_fields.find_by(incident_field_definition_id: definition.id)
      existing || add_custom_field(form, definition)
    else
      raise ArgumentError, "pass either custom_field or system_field"
    end
  end

  def visibility_mode(args, form_field)
    return form_field.visibility_mode unless args.key?(:visible)

    args[:visible] ? IncidentFormField::VISIBILITY_MODE_VISIBLE : IncidentFormField::VISIBILITY_MODE_HIDDEN
  end

  def required_mode(args, form_field)
    return form_field.required_mode unless args.key?(:required)

    args[:required] ? IncidentFormField::REQUIRED_MODE_REQUIRED : IncidentFormField::REQUIRED_MODE_OPTIONAL
  end

  def condition_params(args)
    Array(args[:conditions]).map do |condition|
      IncidentCondition::Values.attributes(@workspace, condition.to_h.with_indifferent_access)
    end
  end

  # Raises rather than skipping, an id the form does not recognize means the
  # page is stale or the payload is wrong, and silently dropping it is what
  # produced a "Field order updated" toast over an order that never changed.
  def field_for_reorder(form, id)
    return ensure_system_field!(form, id.delete_prefix(IncidentFormField::SYNTHETIC_PREFIX)) if id.start_with?(IncidentFormField::SYNTHETIC_PREFIX)

    form.incident_form_fields.find(id)
  end

  def bust_cache(form)
    IncidentFormResolver.bust_cache(form)
  end

  def next_position(form)
    form.incident_form_fields.maximum(:position).to_i + 1
  end

  def move(form_field, direction)
    ActiveRecord::Base.transaction do
      form = form_field.incident_form
      ordered_fields = form.incident_form_fields.ordered.to_a
      current_index = ordered_fields.index(form_field)
      target_index = current_index + direction
      return form_field if target_index.negative? || target_index >= ordered_fields.length

      ordered_fields[current_index], ordered_fields[target_index] = ordered_fields[target_index], ordered_fields[current_index]
      ordered_fields.each_with_index do |field, index|
        field.update!(position: index + 1)
      end

      bust_cache(form)
      form_field.reload
    end
  end

  def normalize_positions!(form)
    form.incident_form_fields.ordered.each_with_index do |field, index|
      next if field.position == index + 1

      field.update!(position: index + 1)
    end
  end
end
