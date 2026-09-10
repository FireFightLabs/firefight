class IncidentFormSettingsSerializer < BaseSerializer
  object_as :incident_form

  attributes(
    slug: { type: :string },
    name: { type: :string },
    lifecycle_event: { type: :string },
    position: { type: :number }
  )

  # Code-default forms get a synthetic `default:<slug>` id, translated back through
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

  # Fields asked by this form or one before it. Anything else would never be answered.
  type "{ id: string; name: string; options: { id: string; name: string }[] }[]"
  def condition_sources
    return [] unless incident_form.persisted?

    incident_form.condition_source_definitions.map do |definition|
      { id: definition.id, name: definition.name,
        options: definition.selectable_values.map { |id, label| { id: id, name: label } } }
    end
  end

  # Hiding Incident Type takes it out of the picker as it does out of the dialog.
  type "string[]"
  def condition_source_system_keys
    return [] unless incident_form.persisted?

    incident_form.condition_source_system_keys
  end

  # Hidden fields included, greyed out. Leaving them out made hiding a one-way door.
  has_many :fields, serializer: IncidentFormFieldSettingsSerializer do
    incident_form.resolved_fields(include_hidden: true)
  end
end
