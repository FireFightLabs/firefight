# One section of a documentation page, found by its words through document, generated from its heading path and text,
# and by its meaning through embedding. The embedding is written by the refresh only for a chunk whose words changed
# (embedded_digest), and one from another embedding model is never compared.
class ProviderDocChunk < ApplicationRecord
  DIMENSIONS = SearchEmbedding::DIMENSIONS

  has_neighbors :embedding, dimensions: DIMENSIONS, normalize: true

  belongs_to :page, class_name: "ProviderDocPage", foreign_key: :provider_doc_page_id, inverse_of: :chunks

  # Chunks with no vector from this model yet, the only ones a refresh sends to be embedded.
  scope :unembedded, ->(model) { where(embedding_model: nil).or(where.not(embedding_model: model)).or(where("embedded_digest IS DISTINCT FROM content_digest")) }

  # A few lines of the section, for a search result, starting where the first word asked about appears.
  SNIPPET_CHARACTERS = 320

  def snippet(words = [])
    flat = text.squish
    at = words.filter_map { |word| flat.downcase.index(word.downcase) }.min.to_i
    start = [ at - (SNIPPET_CHARACTERS / 4), 0 ].max
    piece = flat[start, SNIPPET_CHARACTERS].to_s
    "#{'...' if start.positive?}#{piece}#{'...' if start + SNIPPET_CHARACTERS < flat.length}"
  end
end
