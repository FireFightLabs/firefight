class IncidentFormSettingsSerializer < BaseSerializer
  object_as :incident_form

  attributes(
    slug: { type: :string },
    name: { type: :string },
    lifecycle_event: { type: :string },
    position: { type: :number }
  )

  # Persisted forms expose their DB id. Code-default forms (no DB row yet)
  # get a synthetic id (`default:<slug>`) — the frontend uses it verbatim,
  # and mutation controllers translate it back via
  # `Workspace#ensure_incident_form!` on first edit.
  type :string
  def id
    incident_form.id || "default:#{incident_form.slug}"
  end

  type :boolean
  def is_default
    incident_form.id.nil?
  end

  type :string, optional: true
  def description
    incident_form.description
  end

  type :number
  def field_count
    incident_form.resolved_fields.size
  end

  type "IncidentFormFieldSettings[]"
  def fields
    IncidentFormFieldSettingsSerializer.many(incident_form.resolved_fields)
  end
end
