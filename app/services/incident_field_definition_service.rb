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

  # Every surface names a field the same way, by slug, and hands the same
  # shape in. Mapping that shape onto attributes belongs here rather than once
  # per entry point.
  def upsert!(existing, args)
    attrs = definition_attributes(args, existing)

    existing ? update(existing, attrs) : create(attrs)
  end

  private

  def definition_attributes(args, existing)
    {
      name: args[:name].presence || existing&.name,
      description: args.key?(:description) ? args[:description] : existing&.description,
      field_type: args[:field_type].presence || existing&.field_type,
      option_source: args[:option_source].presence || existing&.option_source,
      catalog_type_id: catalog_type_id(args, existing),
      options: option_params(args, existing)
    }
  end

  def catalog_type_id(args, existing)
    return existing&.catalog_type_id unless args.key?(:catalog_type)
    return nil if args[:catalog_type].blank?

    @workspace.catalog_types.active.find_by!(slug: args[:catalog_type].to_s).id
  end

  # Labels are the only handle an agent has, so an incoming label that
  # already exists reuses that option's row rather than replacing it. That
  # is what keeps a rename from orphaning the incidents pointing at it.
  def option_params(args, existing)
    return existing_option_params(existing) unless args.key?(:options)

    by_label = existing&.incident_field_options&.index_by(&:label) || {}

    Array(args[:options]).filter_map do |label|
      label = label.to_s.strip
      next if label.blank?

      { id: by_label[label]&.id, label: label }
    end
  end

  def existing_option_params(existing)
    return [] unless existing

    existing.incident_field_options.map do |option|
      { id: option.id, label: option.label, disabled: !option.enabled? }
    end
  end

  def next_position
    @workspace.incident_field_definitions.maximum(:position).to_i + 1
  end
end
