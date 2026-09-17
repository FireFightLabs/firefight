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

  # Nearest by meaning, within one workspace. A record whose row was written by another model is
  # left out rather than compared against a vector it cannot be compared with.
  def self.similar_to(query, workspace:, limit: 25)
    vector = FirefightAi.embed(query, workspace: workspace).vectors

    in_workspace(workspace)
      .nearest_neighbors(:vector, vector, distance: "cosine")
      .includes(:embeddable)
      .limit(limit)
      .filter_map { |row| Match.new(record: row.embeddable, similarity: row.neighbor_distance ? 1 - row.neighbor_distance : nil) if row.embeddable }
  end
end
