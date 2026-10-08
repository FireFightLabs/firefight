module ProviderDocs
  # Writes the vector of every chunk whose words changed since it was last embedded, or that an older model embedded, in
  # batches on the deployment's own model. A chunk whose words are the same keeps its vector, so a daily refresh costs
  # only what changed. Without an embedding model the store is still searched by its words.
  module Embedding
    BATCH = 100

    def self.run!(model: FirefightAi.embedding_model, progress: Progress.new)
      progress.embedding_started(ProviderDocChunk.unembedded(model).count)
      written = 0
      ProviderDocChunk.unembedded(model).find_in_batches(batch_size: BATCH) do |chunks|
        vectors, used = FirefightAi.embed_documents(chunks.map { |chunk| text_for(chunk) })
        chunks.zip(vectors).each do |chunk, vector|
          chunk.update_columns(embedding: vector, embedding_model: used, embedded_digest: chunk.content_digest)
        end
        written += chunks.size
        progress.embedded(written)
      end
      progress.embedding_finished(written)
      written
    end

    def self.text_for(chunk) = "#{chunk.heading_path}\n\n#{chunk.text}"
  end
end
