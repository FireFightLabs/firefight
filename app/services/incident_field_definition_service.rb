class IncidentFieldDefinitionService
  def initialize(workspace)
    @workspace = workspace
  end

  def create(attrs)
    ActiveRecord::Base.transaction do
      definition = @workspace.incident_field_definitions.new(
        slug: IncidentFieldDefinition.generate_slug(attrs[:name]),
        name: attrs[:name],
        description: attrs[:description],
        field_type: attrs[:field_type],
        option_source: attrs[:option_source],
        catalog_type_id: attrs[:catalog_type_id],
        position: next_position
      )

      # Built rather than synced so the "at least one enabled option"
      # validation sees them on the same save that creates the definition.
      Array(attrs[:options]).each_with_index do |option, index|
        definition.incident_field_options.build(
          label: option[:label].to_s.strip,
          position: index
        )
      end

      definition.save!
      definition
    end
  end

  def update(definition, attrs)
    ActiveRecord::Base.transaction do
      # Saved after the options are synced, so the "at least one enabled
      # option" rule sees the incoming list rather than the empty one a field
      # switching to a fixed list still has.
      definition.assign_attributes(
        name: attrs[:name],
        description: attrs[:description],
        field_type: attrs[:field_type],
        option_source: attrs[:option_source],
        catalog_type_id: attrs[:catalog_type_id]
      )
      definition.sync_options!(attrs[:options]) if definition.fixed_options?
      definition.save!
      definition
    end
  end

  private

  def next_position
    @workspace.incident_field_definitions.maximum(:position).to_i + 1
  end
end
