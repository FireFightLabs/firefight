# Asking the model for a vector is a call to another system, so it happens here and the rows stay pure.
class SearchEmbeddingService
  def initialize(workspace)
    @workspace = workspace
  end

  # Nothing to embed is not an error, it is a record with nothing worth finding yet. The same words are
  # never sent twice, so a noisy incident costs one embedding per real change rather than one per save.
  def write!(record)
    raise ArgumentError, "#{record.class.name} belongs to another workspace" unless record.workspace.id == @workspace.id

    text = record.search_text.to_s.squish
    return if text.blank?

    digest = SearchEmbedding.digest_for(text)
    embedding = record.search_embedding || record.build_search_embedding(workspace: @workspace)
    return embedding if embedding.persisted? && embedding.content_digest == digest

    result = FirefightAi.embed(text, workspace: @workspace)
    embedding.update!(vector: result.vectors, model: result.model, content_digest: digest)
    embedding
  end

  def similar_to(query, limit: SearchEmbedding::DEFAULT_LIMIT, types: nil)
    vector = FirefightAi.embed(query, workspace: @workspace).vectors
    SearchEmbedding.nearest(vector, workspace: @workspace, limit: limit, types: types)
  end
end
