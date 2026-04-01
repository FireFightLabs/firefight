class IncidentFieldDefinitionService
  def initialize(workspace)
    @workspace = workspace
  end

  def create(name:, description:, field_type:, option_source:, config: {})
    ActiveRecord::Base.transaction do
      @workspace.incident_field_definitions.create!(
        key: IncidentFieldDefinition.generate_key(name),
        name: name,
        description: description,
        field_type: field_type,
        option_source: option_source,
        config: config,
        position: next_position
      )
    end
  end

  def update(field_definition, attrs)
    ActiveRecord::Base.transaction do
      field_definition.update!(attrs)
      field_definition
    end
  end

  private

  def next_position
    @workspace.incident_field_definitions.maximum(:position).to_i + 1
  end
end
