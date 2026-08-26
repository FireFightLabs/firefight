class Api::V1::Catalog::TypesController < Api::V1::ApiController
  def index
    authorize!(Ability::Action::RESOURCE_CATALOG, Ability::Action::ACTION_READ)
    @types = current_workspace.catalog_types.active.ordered.includes(:catalog_attribute_definitions)
  end

  def show
    authorize!(Ability::Action::RESOURCE_CATALOG, Ability::Action::ACTION_READ)
    @type = find_type!
  end

  def create
    authorize!(Ability::Action::RESOURCE_CATALOG, Ability::Action::ACTION_CREATE)

    @type = CatalogType::Upsert.new(current_workspace).call(nil, type_params)
    render :show, status: :created
  end

  def update
    authorize!(Ability::Action::RESOURCE_CATALOG, Ability::Action::ACTION_UPDATE)

    @type = CatalogType::Upsert.new(current_workspace).call(find_type!, type_params)
    render :show
  end

  def destroy
    authorize!(Ability::Action::RESOURCE_CATALOG, Ability::Action::ACTION_DELETE)

    type = find_type!
    blocked_reason = type.deletion_blocked_reason
    return render json: error_response("validation_error", blocked_reason), status: :unprocessable_entity if blocked_reason

    type.soft_delete!
    head :no_content
  end

  private

  def find_type!
    current_workspace.catalog_types.active.includes(:catalog_attribute_definitions).find_by!(slug: params[:slug])
  end

  def type_params
    params.permit(
      :name, :description, :icon, :color,
      attributes: [ :name, :attribute_type, :required, :role, :reference_type, options: [] ]
    ).to_h.deep_symbolize_keys
  end
end
