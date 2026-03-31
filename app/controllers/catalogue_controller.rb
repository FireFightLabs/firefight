class CatalogueController < InertiaController
  before_action :require_authentication

  def index
    types = current_workspace.catalog_types.active.ordered.with_entry_counts
      .includes(:catalog_attribute_definitions)

    render inertia: "catalogue/index", props: {
      types: CatalogTypeSerializer.many(types)
    }
  end

  def show
    type = current_workspace.catalog_types.active.find_by!(slug: params[:type_slug])
    entries = type.catalog_entries.active.ordered.with_relationships

    all_types = current_workspace.catalog_types.active.ordered
      .includes(:catalog_attribute_definitions)

    render inertia: "catalogue/show", props: {
      type: CatalogTypeSerializer.one(type),
      entries: CatalogEntrySerializer.many(entries),
      allTypes: CatalogTypeSerializer.many(all_types),
      referenceEntries: type.reference_entry_options
    }
  end

  def create_type
    next_position = current_workspace.catalog_types.maximum(:position).to_i + 1
    slug = generate_slug(params[:name])

    type = current_workspace.catalog_types.create!(
      name: params[:name],
      slug: slug,
      kind: CatalogType::KIND_CUSTOM,
      description: params[:description],
      icon: params[:icon],
      color: params[:color],
      position: next_position
    )

    if params[:attribute_definitions].present?
      type.sync_attribute_definitions!(parse_attribute_definitions)
    end

    redirect_to catalogue_type_path(type.slug)
  rescue ActiveRecord::RecordInvalid => e
    redirect_back fallback_location: catalogue_path,
      inertia: { errors: e.record.errors.to_hash }
  end

  def update_type
    type = current_workspace.catalog_types.active.find(params[:id])

    type.update!(
      name: params[:name],
      description: params[:description],
      icon: params[:icon],
      color: params[:color]
    )

    if params[:attribute_definitions].present?
      type.sync_attribute_definitions!(parse_attribute_definitions)
    end

    redirect_to catalogue_type_path(type.slug)
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotDestroyed => e
    redirect_back fallback_location: catalogue_path,
      inertia: { errors: { base: [ e.message ] } }
  end

  def destroy_type
    type = current_workspace.catalog_types.active.find(params[:id])
    type.soft_delete!
    redirect_to catalogue_path
  rescue ActiveRecord::RecordNotDestroyed => e
    redirect_back fallback_location: catalogue_path,
      inertia: { errors: { base: [ e.message ] } }
  end

  def create_entry
    type = current_workspace.catalog_types.active.find_by!(slug: params[:type_slug])
    slug = generate_slug(params[:name])

    entry = type.catalog_entries.new(
      workspace: current_workspace,
      name: params[:name],
      slug: slug
    )

    raw_attrs = params[:attributes]&.to_unsafe_h || {}
    _scalar_attrs, reference_attrs = entry.assign_validated_attributes!(raw_attrs)
    entry.save!
    entry.sync_references!(reference_attrs)

    redirect_to catalogue_type_path(type.slug)
  rescue ActiveRecord::RecordInvalid => e
    redirect_back fallback_location: catalogue_type_path(params[:type_slug]),
      inertia: { errors: { base: [ e.message ] } }
  end

  def update_entry
    entry = current_workspace.catalog_entries.where(deleted_at: nil).find(params[:id])

    entry.name = params[:name] if params[:name].present?

    raw_attrs = params[:attributes]&.to_unsafe_h || {}
    _scalar_attrs, reference_attrs = entry.assign_validated_attributes!(raw_attrs)
    entry.save!
    entry.sync_references!(reference_attrs)

    redirect_to catalogue_type_path(entry.catalog_type.slug)
  rescue ActiveRecord::RecordInvalid => e
    redirect_back fallback_location: catalogue_path,
      inertia: { errors: { base: [ e.message ] } }
  end

  def destroy_entry
    entry = current_workspace.catalog_entries.where(deleted_at: nil).find(params[:id])
    entry.soft_delete!
    redirect_to catalogue_type_path(entry.catalog_type.slug)
  end

  private

  def generate_slug(name)
    name.to_s.strip.downcase.gsub(/\s+/, "_").gsub(/[^a-z0-9_]/, "")
  end

  def parse_attribute_definitions
    params[:attribute_definitions].map do |d|
      {
        id: d[:id],
        name: d[:name],
        attribute_type: d[:attribute_type] || d[:attributeType],
        required: ActiveModel::Type::Boolean.new.cast(d[:required]),
        config: d[:config]&.to_unsafe_h || {}
      }
    end
  end
end
