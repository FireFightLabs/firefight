# The dashboard's search, the same one Halon and outside agents run through search_map. It answers in JSON for a search
# box, so a person who reads no part of the map is told why rather than redirected away.
class MapSearchController < InertiaController
  NO_MAP_REACH = "You cannot see any part of the map, so search finds nothing. An admin decides which environments you see.".freeze

  def index
    @web_authorization = AbilityGateway.authorize!(
      principal: current_membership, action_key: Ability::Action::MAP_READ, workspace: current_workspace,
      params: web_authorization_params, context: { source: AbilityGateway::SOURCE_WEB }
    )
    page = MapSearchService.new(current_workspace, current_membership).search(params[:q].to_s)
    render json: { results: MapSearchResultSerializer.many(page.results), refusal: nil }
  rescue AbilityGateway::Denied
    render json: { results: [], refusal: NO_MAP_REACH }
  end
end
