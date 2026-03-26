class CatalogueController < InertiaController
  before_action :require_authentication

  def index
    render inertia: "catalogue/index"
  end

  def show
    render inertia: "catalogue/show", props: {
      typeSlug: params[:type_slug]
    }
  end
end
