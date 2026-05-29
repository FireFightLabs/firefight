class Api::V1::Catalog::EntriesController < Api::V1::ApiController
  def index
    authorize!(ApiKey::RESOURCE_CATALOG, ApiKey::ACTION_READ)
    type = find_type!
    scope = type.catalog_entries.active.ordered.with_relationships
    @entries, @pagination = paginate(scope)
  end

  def show
    authorize!(ApiKey::RESOURCE_CATALOG, ApiKey::ACTION_READ)
    @entry = current_workspace.catalog_entries.active.with_relationships.find(params[:id])
  end

  def create
    authorize!(ApiKey::RESOURCE_CATALOG, ApiKey::ACTION_CREATE)
    type = find_type!

    @entry = entry_service.upsert(
      type: type,
      name: params.require(:name),
      raw_attributes: attributes_param,
      source: params[:source],
      external_id: params[:external_id]
    )
    render :show, status: @entry.previously_new_record? ? :created : :ok
  end

  def update
    authorize!(ApiKey::RESOURCE_CATALOG, ApiKey::ACTION_UPDATE)
    @entry = current_workspace.catalog_entries.active.find(params[:id])
    entry_service.update(@entry, name: params[:name], raw_attributes: attributes_param)
    @entry.reload
    render :show, status: :ok
  end

  def destroy
    authorize!(ApiKey::RESOURCE_CATALOG, ApiKey::ACTION_DELETE)
    entry = current_workspace.catalog_entries.active.find(params[:id])
    entry_service.delete(entry)
    head :no_content
  end

  private

  def find_type!
    current_workspace.catalog_types.active.find_by!(slug: params[:slug])
  end

  def entry_service
    @entry_service ||= Catalogue::EntryService.new(current_workspace)
  end

  def attributes_param
    raw = params[:attributes]
    return {} if raw.blank?

    raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : raw.to_h
  end
end
