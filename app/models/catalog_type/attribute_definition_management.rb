module CatalogType::AttributeDefinitionManagement
  extend ActiveSupport::Concern

  def sync_attribute_definitions!(definitions_params)
    existing = catalog_attribute_definitions.index_by(&:id)
    submitted_ids = definitions_params.filter_map { |d| d[:id] }

    definitions_params.each_with_index do |def_params, index|
      if def_params[:id] && (existing_def = existing[def_params[:id]])
        update_attribute_definition!(existing_def, def_params, index)
      else
        create_attribute_definition!(def_params, index)
      end
    end

    removed_ids = existing.keys - submitted_ids
    removed_ids.each { |id| remove_attribute_definition!(existing[id]) }
  end

  private

  def create_attribute_definition!(params, position)
    catalog_attribute_definitions.create!(
      slug: generate_slug(params[:name]),
      name: params[:name],
      attribute_type: params[:attribute_type],
      required: params[:required] || false,
      position: position,
      role: params[:role].presence,
      config: params[:config] || {}
    )
  end

  def update_attribute_definition!(attr_def, params, position)
    updates = { name: params[:name], required: params[:required] || false, position: position }
    # Only callers that send the key touch the role, so an update path that
    # does not know about roles cannot silently clear them.
    updates[:role] = params[:role].presence if params.key?(:role)

    if params[:config]
      validate_config_update!(attr_def, params[:config])
      updates[:config] = params[:config]
    end

    attr_def.update!(updates)
  end

  def remove_attribute_definition!(attr_def)
    if system?
      raise ActiveRecord::RecordNotDestroyed, "Cannot remove system attribute definitions"
    end

    if attr_def.reference?
      if attr_def.catalog_entry_relationships.exists?
        raise ActiveRecord::RecordNotDestroyed,
          "Cannot remove attribute '#{attr_def.name}' because it has active relationships"
      end
    else
      active_entries = catalog_entries.where(deleted_at: nil)
      if active_entries.where("attributes ? :key", key: attr_def.slug).exists?
        raise ActiveRecord::RecordNotDestroyed,
          "Cannot remove attribute '#{attr_def.name}' because it is used by active entries"
      end
    end

    attr_def.destroy!
  end

  def validate_config_update!(attr_def, new_config)
    if attr_def.reference?
      old_ref = attr_def.config["reference_type_id"]
      new_ref = new_config["reference_type_id"]
      if old_ref.present? && new_ref.present? && old_ref != new_ref
        raise ActiveRecord::RecordNotDestroyed,
          "Cannot change reference target type for '#{attr_def.name}'"
      end
      return
    end

    return unless attr_def.select?

    old_options = attr_def.config["options"] || []
    new_options = new_config["options"] || []
    removed_options = old_options - new_options

    return if removed_options.empty?

    active_entries = catalog_entries.where(deleted_at: nil)
    removed_options.each do |option|
      if active_entries.where("attributes ->> :key = :val", key: attr_def.slug, val: option).exists?
        raise ActiveRecord::RecordNotDestroyed,
          "Cannot remove option '#{option}' from '#{attr_def.name}' because it is used by active entries"
      end
    end
  end

  def generate_slug(name)
    name.to_s.strip.downcase.gsub(/\s+/, "_").gsub(/[^a-z0-9_]/, "")
  end
end
