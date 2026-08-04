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
  # first edit keeps the code defaults as the single source of truth: a row
  # only ever means "this workspace overrode something".
  def ensure_system_field!(form, system_field_key)
    existing = form.incident_form_fields.find_by(
      field_source_kind: IncidentFormField::FIELD_SOURCE_KIND_SYSTEM,
      system_field_key: system_field_key
    )
    return existing if existing

    definition = IncidentSystemField.fetch(system_field_key)
    default_position = IncidentSystemField.defaults_for(form.lifecycle_event).index(definition)
    raise ArgumentError, "#{system_field_key} does not appear on the #{form.lifecycle_event} form" if default_position.nil?

    mode = definition.required_mode_for(form.lifecycle_event)
    # "available" describes how a field ships, not a stored mode: on the row it
    # is simply hidden and optional until someone turns it on.
    available = mode == IncidentFormField::REQUIRED_MODE_AVAILABLE

    form.incident_form_fields.create!(
      field_source_kind: IncidentFormField::FIELD_SOURCE_KIND_SYSTEM,
      system_field_key: system_field_key,
      position: default_position,
      visibility_mode: available ? IncidentFormField::VISIBILITY_MODE_HIDDEN : IncidentFormField::VISIBILITY_MODE_VISIBLE,
      required_mode: available ? IncidentFormField::REQUIRED_MODE_OPTIONAL : mode
    )
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

  def reorder(form, ordered_ids)
    ActiveRecord::Base.transaction do
      fields = form.incident_form_fields.where(id: ordered_ids).index_by(&:id)
      ordered_ids.each_with_index do |id, index|
        field = fields[id]
        next unless field
        field.update!(position: index + 1) unless field.position == index + 1
      end
      bust_cache(form)
    end
  end

  private

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
