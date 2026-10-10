# Splits a handbook page into sections for search, and embeds each section whose words changed on the deployment's
# embedding model, recorded against the workspace. Without a model the page is still searched by its words.
class HandbookIndexJob < ApplicationJob
  queue_as :default

  discard_on ActiveRecord::RecordNotFound

  def perform(page_id)
    page = Chat::HandbookPage.find(page_id)
    page.rechunk!
    model = FirefightAi.embedding_model
    page.chunks.unembedded(model).find_each do |chunk|
      result = FirefightAi.embed(chunk.embedded_text, workspace: page.workspace)
      chunk.update_columns(embedding: result.vectors, embedding_model: result.model, embedded_digest: chunk.content_digest)
    end
  rescue FirefightAi::Error => error
    Rails.logger.info({ event: "handbook.index_unembedded", page_id: page_id, error: error.class.name }.to_json)
  end
end
