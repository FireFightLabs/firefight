# Something a sweep saw change on a resource. Facts, never conclusions, so they need no confirming.
class ResourceMap::Change < ApplicationRecord
  self.table_name = "resource_map_changes"

  KIND_APPEARED = "appeared".freeze
  KIND_REMOVED = "removed".freeze
  KIND_DEPLOYED = "deployed".freeze
  KIND_STATUS_CHANGED = "status_changed".freeze
  KINDS = [ KIND_APPEARED, KIND_REMOVED, KIND_DEPLOYED, KIND_STATUS_CHANGED ].freeze

  belongs_to :workspace
  belongs_to :resource, class_name: "ResourceMap::Resource"

  validates :kind, inclusion: { in: KINDS }

  scope :newest_first, -> { order(happened_at: :desc) }
  scope :since, ->(time) { where(happened_at: time..) }
end
