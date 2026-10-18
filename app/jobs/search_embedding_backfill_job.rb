# Writes a vector for every incident, finding and postmortem that has none, such as those from before similarity search
# shipped. Started by hand (bin/rails search:backfill_embeddings). It takes a batch at a time, hands each record to the
# same job a changed record gets, so the same AI rules apply and the same account pays, and queues itself for the next
# batch from where it stopped. Starting it again, or reaching a record already written, never writes a vector twice.
class SearchEmbeddingBackfillJob < ApplicationJob
  queue_as :background

  TYPES = [ Incident.name, Investigation::Finding.name, Postmortem.name ].freeze
  BATCH = 200
  # Spaces the batches out, so the embedding provider is never sent a workspace's whole history at once.
  PAUSE = 1.minute

  # type_index is where in TYPES the backfill is, after_id the last record of that kind it reached.
  def perform(type_index = 0, after_id = nil)
    type = TYPES.fetch(type_index)
    batch = batch_of(type.constantize, after_id)
    if batch.empty?
      self.class.perform_later(type_index + 1) if type_index + 1 < TYPES.size
      return
    end

    ActiveJob.perform_all_later(batch.select(&:search_embeddable?).map { |record| WriteSearchEmbeddingJob.new(type, record.id) })
    self.class.set(wait: PAUSE).perform_later(type_index, batch.last.id)
  end

  private

  def batch_of(klass, after_id)
    missing = klass.search_embedding_candidates.where.missing(:search_embedding).order(:id)
    missing = missing.where(klass.arel_table[:id].gt(after_id)) if after_id
    missing.limit(BATCH).to_a
  end
end
