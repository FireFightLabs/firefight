# Indexes whatever has no search row yet, such as everything that existed before search did. Hourly, and a pass with
# nothing missing costs one query per type. A catalog entry indexed here is embedded too, once, since its description
# is what a search by meaning reads.
class SearchDocumentBackfillJob < ApplicationJob
  queue_as :background

  BATCH = 1_000

  def perform
    SearchDocument::TYPES.each do |type|
      klass = SearchDocument.class_for(type)
      klass.search_document_candidates.where.missing(:search_document).in_batches(of: BATCH) do |batch|
        ids = batch.pluck(:id)
        SearchDocument.index!(klass, ids)
        klass.where(id: ids).find_each(&:schedule_search_embedding) if klass.include?(SearchEmbedding::Writing)
      end
    end
  end
end
