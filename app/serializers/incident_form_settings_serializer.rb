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
    incident_form.incident_form_fields.size
  end

  has_many :incident_form_fields, as: :fields, serializer: IncidentFormFieldSettingsSerializer
end
