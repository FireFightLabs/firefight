# What a record contributes to search, and when it is rewritten. The writing itself is
# SearchEmbeddingService, since it asks the model for the vector.
module SearchEmbedding::Writing
  extend ActiveSupport::Concern

  included do
    has_one :search_embedding, as: :embeddable, dependent: :destroy

    # The job re-reads the record and writes nothing when the words have not changed.
    after_commit :schedule_search_embedding, on: [ :create, :update ]
  end

  def schedule_search_embedding
    return unless search_embeddable?

    WriteSearchEmbeddingJob.perform_later(self.class.name, id)
  end

  # A record says when it is worth embedding. Most are worth it as soon as they exist.
  def search_embeddable? = true
end
