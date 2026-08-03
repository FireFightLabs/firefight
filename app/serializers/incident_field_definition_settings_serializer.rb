class IncidentFieldDefinitionSettingsSerializer < BaseSerializer
  object_as :field_definition

  attributes(
    id: { type: :string },
    key: { type: :string },
    name: { type: :string },
    field_type: { type: :string },
    option_source: { type: :string },
    position: { type: :number }
  )

  type :string, optional: true
  def description
    field_definition.description
  end

  # Named for the association rather than `options`: Oj::Serializer defines its
  # own `options`, and a matching name reads that instead of the model.
  has_many :incident_field_options, as: :options, serializer: IncidentFieldOptionSerializer

  type :string, optional: true
  def catalog_type_id
    field_definition.catalog_type_id
  end

  type :string, optional: true
  def catalog_type_name
    field_definition.catalog_type&.name
  end

  type :number
  def usage_count
    field_definition.usage_count
  end

  type :boolean
  def enabled
    field_definition.enabled?
  end

  type :string, optional: true
  def deletion_blocked_reason
    field_definition.deletion_blocked_reason
  end

  type :string, optional: true
  def shape_change_blocked_reason
    field_definition.shape_change_blocked_reason
  end
end
