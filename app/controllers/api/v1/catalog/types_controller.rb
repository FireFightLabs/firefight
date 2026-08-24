class Api::V1::Catalog::TypesController < Api::V1::ApiController
  def index
    authorize!(Ability::Action::RESOURCE_CATALOG, Ability::Action::ACTION_READ)
    @types = current_workspace.catalog_types.active.ordered.includes(:catalog_attribute_definitions)
  end

  def show
    authorize!(Ability::Action::RESOURCE_CATALOG, Ability::Action::ACTION_READ)
    @type = current_workspace.catalog_types.active.includes(:catalog_attribute_definitions).find_by!(slug: params[:slug])
  end
end
