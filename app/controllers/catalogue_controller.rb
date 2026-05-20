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
    all_types = current_workspace.catalog_types.active.ordered.includes(:catalog_attribute_definitions)

    render inertia: "catalogue/type", props: {
      type: CatalogTypeSerializer.one(type),
      entries: CatalogEntrySerializer.many(entries),
      allTypes: CatalogTypeSerializer.many(all_types),
      referenceEntries: type.reference_entry_options,
      workspaceMembers: member_resolution_service.resolve_for_entries(entries, type)
    }
  end

  def search_members
    render json: current_workspace.adapter.list_members
  end

  def search_channels
    render json: current_workspace.adapter.list_channels
  end

  def create_type
    type = CatalogType.create_custom!(
      workspace: current_workspace,
      name: params[:name], description: params[:description],
      icon: params[:icon], color: params[:color],
      attribute_definitions: parse_attribute_definitions
    )
    redirect_to catalogue_type_path(type.slug)
  rescue ActiveRecord::RecordInvalid => e
    redirect_back fallback_location: catalogue_path, inertia: { errors: e.record.errors.to_hash }
  end

  def update_type
    type = current_workspace.catalog_types.active.find(params[:id])
    type.update_with_definitions!(
      { name: params[:name], description: params[:description], icon: params[:icon], color: params[:color] },
      attribute_definitions: parse_attribute_definitions
    )
    redirect_to catalogue_type_path(type.slug)
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotDestroyed => e
    redirect_back fallback_location: catalogue_path, inertia: { errors: { base: [ e.message ] } }
  end

  def destroy_type
    type = current_workspace.catalog_types.active.find(params[:id])
    type.soft_delete!
    redirect_to catalogue_path
  rescue ActiveRecord::RecordNotDestroyed => e
    redirect_back fallback_location: catalogue_path, inertia: { errors: { base: [ e.message ] } }
  end

  def create_entry
    type = current_workspace.catalog_types.active.find_by!(slug: params[:type_slug])
    entry_service.create(type: type, name: params[:name], raw_attributes: params[:attributes]&.to_unsafe_h || {})
    redirect_to catalogue_type_path(type.slug)
  rescue ActiveRecord::RecordInvalid => e
    redirect_back fallback_location: catalogue_type_path(params[:type_slug]), inertia: { errors: { base: [ e.message ] } }
  end

  def update_entry
    entry = current_workspace.catalog_entries.where(deleted_at: nil).find(params[:id])
    entry_service.update(entry, name: params[:name], raw_attributes: params[:attributes]&.to_unsafe_h || {})
    redirect_to catalogue_type_path(entry.catalog_type.slug)
  rescue ActiveRecord::RecordInvalid => e
    redirect_back fallback_location: catalogue_path, inertia: { errors: { base: [ e.message ] } }
  end

  def destroy_entry
    entry = current_workspace.catalog_entries.where(deleted_at: nil).find(params[:id])
    entry_service.delete(entry)
    redirect_to catalogue_type_path(entry.catalog_type.slug)
  end

  private

  def entry_service
    @entry_service ||= Catalogue::EntryService.new(current_workspace)
  end

  def member_resolution_service
    @member_resolution_service ||= Catalogue::MemberResolutionService.new(current_workspace)
  end

  def parse_attribute_definitions
    return [] unless params[:attribute_definitions].present?

    params[:attribute_definitions].map do |d|
      config = d[:config]&.to_unsafe_h || {}
      config["options"] = Array(d[:options]) if d[:options].present?
      ref_id = d[:referenceTypeId] || d[:reference_type_id]
      config["reference_type_id"] = ref_id if ref_id.present?

      {
        id: d[:id],
        name: d[:name],
        attribute_type: d[:attribute_type] || d[:attributeType],
        required: ActiveModel::Type::Boolean.new.cast(d[:required]),
        config: config
      }
    end
  end
end
