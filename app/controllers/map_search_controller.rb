# The dashboard's search, the same one Halon and outside agents run through search_map.
class MapSearchController < InertiaController
  authorizes Ability::Action::RESOURCE_MAP, read: %i[index]

  def index
    page = MapSearchService.new(current_workspace, current_membership).search(params[:q].to_s)
    render json: MapSearchResultSerializer.many(page.results)
  end
end
