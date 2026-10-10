# One section of a handbook page, found by its words and by its meaning, as the providers' documentation is
# (ProviderDocChunk). The page is encrypted, so the section's words are too, and its index keeps the words without
# where they sit, so the index cannot be read back into the page.
class Chat::HandbookChunk < ApplicationRecord
  self.table_name = "chat_handbook_chunks"

  DIMENSIONS = SearchEmbedding::DIMENSIONS

  has_neighbors :embedding, dimensions: DIMENSIONS, normalize: true
  encrypts :heading_path, :text

  belongs_to :workspace
  belongs_to :page, class_name: "Chat::HandbookPage", foreign_key: :handbook_page_id, inverse_of: :chunks

  before_validation :index_words, if: -> { new_record? || will_save_change_to_text? }

  scope :unembedded, ->(model) { where(embedding_model: nil).or(where.not(embedding_model: model)).or(where("embedded_digest IS DISTINCT FROM content_digest")) }

  def snippet(words = []) = ProviderDocChunk.new(text: text).snippet(words)

  # What is embedded, the headings above the section with its words.
  def embedded_text = "#{heading_path}\n\n#{text}"

  private

  def index_words
    self.document = self.class.connection.select_value(
      self.class.sanitize_sql_array([ "SELECT strip(to_tsvector('simple', ?))::text", "#{heading_path} #{text}" ])
    )
  end
end
