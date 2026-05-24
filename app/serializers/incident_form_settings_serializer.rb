class IncidentFormSettingsSerializer < BaseSerializer
  object_as :incident_form

  attributes(
    id: { type: :string },
    slug: { type: :string },
    name: { type: :string },
    lifecycle_event: { type: :string },
    position: { type: :number }
  )

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
