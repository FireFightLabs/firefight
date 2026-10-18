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

  class_methods do
    # What a backfill reads in these workspaces to ask search_embeddable? of each record, with whatever that question loads.
    def search_embedding_candidates(workspace_ids) = where(workspace_id: workspace_ids)
  end
end
