# Indexes records for search in one go, such as every resource a sweep changed.
class SearchDocumentIndexJob < ApplicationJob
  queue_as :background

  def perform(type, ids)
    SearchDocument.index!(SearchDocument.class_for(type), ids)
  end
end
