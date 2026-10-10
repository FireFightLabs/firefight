# The providers' documentation search, run over one workspace's handbook pages. It ranks by words and by meaning and
# merges the two by reciprocal rank fusion. A section's words are kept without their positions, so they are ranked by how often they appear rather than
# how close they sit.
class Chat::HandbookChunk::Search < ProviderDocChunk::Search
  def initialize(query, workspace:, model: nil, meaning: nil)
    super(query, providers: [], model: model, meaning: meaning)
    @workspace = workspace
  end

  private

  def searchable? = @workspace.present?

  def chunk_class = Chat::HandbookChunk

  def scope = Chat::HandbookChunk.where(workspace: @workspace)

  def rank_sql = "ts_rank(document, to_tsquery('simple', ?)) DESC"
end
