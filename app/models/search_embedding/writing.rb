# What a record contributes to search, and when it is rewritten.
module SearchEmbedding::Writing
  extend ActiveSupport::Concern

  included do
    has_one :search_embedding, as: :embeddable, dependent: :destroy

    # The job re-reads the record and writes nothing when the words have not changed, so a noisy
    # incident costs one embedding per real change rather than one per save.
    after_commit :schedule_search_embedding, on: [ :create, :update ]
  end

  def schedule_search_embedding
    return unless search_embeddable?

    WriteSearchEmbeddingJob.perform_later(self.class.name, id)
  end

  # A record says when it is worth embedding. Most are worth it as soon as they exist.
  def search_embeddable? = true

  # Nothing to embed is not an error, it is a record with nothing worth finding yet.
  def write_search_embedding!
    text = search_text.to_s.squish
    return if text.blank?

    digest = SearchEmbedding.digest_for(text)
    embedding = search_embedding || build_search_embedding(workspace: workspace)
    return embedding if embedding.persisted? && embedding.content_digest == digest

    result = FirefightAi.embed(text, workspace: workspace)
    embedding.update!(vector: result.vectors, model: result.model, content_digest: digest)
    embedding
  end
end
