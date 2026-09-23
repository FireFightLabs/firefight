# One vector per record, so the agent can ask what looks like this rather than what matches these
# words. The model that writes them is configured on its own, since changing it means rewriting all.
class SearchEmbedding < ApplicationRecord
  DIMENSIONS = 1536

  has_neighbors :vector, dimensions: DIMENSIONS, normalize: true

  belongs_to :workspace
  belongs_to :embeddable, polymorphic: true

  validates :model, :content_digest, presence: true

  scope :in_workspace, ->(workspace) { where(workspace_id: workspace.id) }
  scope :of_type, ->(types) { where(embeddable_type: types) }

  def self.digest_for(text) = Digest::SHA256.hexdigest(text.to_s)

  Match = Data.define(:record, :similarity) do
    def kind = record.class.name.demodulize.underscore

    def facts = record.search_facts
  end

  DEFAULT_LIMIT = 25

  # Nearest by meaning, within one workspace. Rows written by an older embedding model are left
  # out, since a vector from one model says nothing about a vector from another.
  def self.nearest(vector, workspace:, limit: DEFAULT_LIMIT, types: nil)
    scope = in_workspace(workspace).where(model: FirefightAi.embedding_model)
    scope = scope.of_type(types) if types

    scope.nearest_neighbors(:vector, vector, distance: "cosine")
      .includes(:embeddable)
      .limit(limit)
      .filter_map { |row| match_for(row) }
  end

  def self.match_for(row)
    return nil unless row.embeddable

    Match.new(record: row.embeddable, similarity: row.neighbor_distance ? 1 - row.neighbor_distance : nil)
  end
end
