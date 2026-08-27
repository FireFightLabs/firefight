class IncidentFormSettingsSerializer < BaseSerializer
  object_as :incident_form

  attributes(
    slug: { type: :string },
    name: { type: :string },
    lifecycle_event: { type: :string },
    position: { type: :number }
  )

  # Persisted forms expose their DB id. Code-default forms (no DB row yet)
  # get a synthetic id (`default:<slug>`), the frontend uses it verbatim,
  # and mutation controllers translate it back via
  # `Workspace#ensure_incident_form!` on first edit.
  type :string
  def id
    incident_form.id || "#{IncidentFormField::SYNTHETIC_PREFIX}#{incident_form.slug}"
  end

  type :boolean
  def is_default
    incident_form.id.nil?
  end

  type :string, optional: true
  def description
    incident_form.description
  end

  # Custom fields a condition on this form may read, asked for by this form, or
  # by one that runs before it. Anything else would never be answered.
  type "{ id: string; name: string; options: { id: string; name: string }[] }[]"
  def condition_sources
    return [] unless incident_form.persisted?

    incident_form.condition_source_definitions.map do |definition|
      { id: definition.id, name: definition.name,
        options: definition.selectable_values.map { |id, label| { id: id, name: label } } }
    end
  end

  # Which of the two built-in sources this form asks for. Hiding Incident Type
  # takes it out of the picker, the same way it takes it out of the dialog.
  type "string[]"
  def condition_source_system_keys
    return [] unless incident_form.persisted?

    incident_form.condition_source_system_keys
  end

  # Hidden fields included, greyed out in the editor. Leaving them out is what
  # made hiding a field a one-way door.
  has_many :fields, serializer: IncidentFormFieldSettingsSerializer do
    incident_form.resolved_fields(include_hidden: true)
  end
end
