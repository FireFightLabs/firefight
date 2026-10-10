# Finds the sections of providers' documentation that answer a question, from two lists merged by reciprocal rank
# fusion: Postgres full text over each chunk's words, which finds an exact name such as firefight.sha, an endpoint path
# or an error message, and nearest by meaning over the chunks' embeddings, which finds a question asked in other words.
# Only the providers named are searched. meaning is called for the query's vector only when some chunk of those
# providers has one from the current model, so a store not embedded yet costs no model call and still answers by words.
# The handbook's search is the same search over a workspace's pages (Chat::HandbookChunk::Search), which names its own
# chunks and how they are ranked by their words.
class ProviderDocChunk::Search
  DEFAULT_LIMIT = 5
  MAX_LIMIT = 10
  CANDIDATES = 50
  # The usual constant for reciprocal rank fusion, as SearchDocument::Search uses.
  FUSION_K = 60

  Hit = Data.define(:chunk, :matched_by)

  attr_reader :query, :providers

  def initialize(query, providers:, model: nil, meaning: nil)
    @query = query.to_s.squish
    @providers = Array(providers).map(&:to_s).uniq
    @model = model
    @meaning = meaning
  end

  def hits(limit: DEFAULT_LIMIT)
    return [] if @query.blank? || !searchable?

    size = limit.to_i.positive? ? [ limit.to_i, MAX_LIMIT ].min : DEFAULT_LIMIT
    lists = { words: word_matches, meaning: meaning_matches }
    scores = Hash.new(0.0)
    matched_by = Hash.new { |hash, key| hash[key] = [] }
    lists.each do |match, ids|
      ids.each_with_index do |id, rank|
        scores[id] += 1.0 / (FUSION_K + rank + 1)
        matched_by[id] << match
      end
    end
    best = scores.keys.sort_by { |id| [ -scores[id], id ] }.first(size)
    chunks = chunk_class.where(id: best).includes(:page).index_by(&:id)
    best.filter_map { |id| chunks[id] && Hit.new(chunk: chunks[id], matched_by: matched_by[id]) }
  end

  # The query's own words, as the chunks' document splits them, so a dotted name or a path is one word on both sides.
  def words
    @words ||= begin
      lexemes = ProviderDocChunk.connection.select_values(
        ProviderDocChunk.sanitize_sql_array([ "SELECT unnest(tsvector_to_array(to_tsvector('simple', ?)))", @query ])
      )
      meaningful = lexemes.reject { |lexeme| Chat::Memory::Words::STOP_WORDS.include?(lexeme) }
      meaningful.presence || lexemes
    end
  end

  private

  def searchable? = @providers.any?

  def chunk_class = ProviderDocChunk

  def scope = ProviderDocChunk.where(provider: @providers)

  # Cover density, which reads how close the words sit, since a provider's chunk keeps where each word is.
  def rank_sql = "ts_rank_cd(document, to_tsquery('simple', ?), 32) DESC"

  # Every word as its own alternative, ranked by how densely they sit in a section, so a section holding all of them
  # comes before one holding a single common word.
  def word_matches
    return [] if words.empty?

    tsquery = words.map { |word| "'#{word.delete("'\\")}'" }.join(" | ")
    scope.where("document @@ to_tsquery('simple', ?)", tsquery)
         .order(Arel.sql(ProviderDocChunk.sanitize_sql_array([ rank_sql, tsquery ])))
         .order(:id).limit(CANDIDATES).pluck(:id)
  end

  def meaning_matches
    return [] unless @meaning && @model && scope.where(embedding_model: @model).where.not(embedding: nil).exists?

    vector = @meaning.call
    return [] unless vector

    scope.where(embedding_model: @model).nearest_neighbors(:embedding, vector, distance: "cosine").limit(CANDIDATES).pluck(:id)
  end
end
