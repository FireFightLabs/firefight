# One search across the map, the catalog and confirmed memories, for the dashboard and for Halon and outside agents. A
# catalog entry is also found by what its description means, which asks the embedding model for the query's vector, so
# that call lives here and is made only when the search could use it. A search without it still answers by words.
class MapSearchService
  def initialize(workspace, principal)
    @workspace = workspace
    @principal = principal
  end

  def search(query, types: nil, filters: {}, limit: SearchDocument::Search::DEFAULT_LIMIT, cursor: nil)
    SearchDocument.search(@workspace, query, principal: @principal, types: types, filters: filters, limit: limit, cursor: cursor,
                                             meaning: -> { meaning_of(query) })
  end

  private

  def meaning_of(query)
    return nil unless Entitlements.allows?(@workspace, Entitlements::AI)

    SearchEmbeddingService.new(@workspace).query_vector(query)
  rescue FirefightAi::Error => error
    Rails.logger.warn({ event: "map_search.meaning_unavailable", workspace_id: @workspace.id, error: error.class.name, message: error.message }.to_json)
    nil
  end
end
