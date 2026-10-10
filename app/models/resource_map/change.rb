# Something a sweep saw change on a resource. Facts, never conclusions, so they need no confirming.
class ResourceMap::Change < ApplicationRecord
  self.table_name = "resource_map_changes"

  KIND_APPEARED = "appeared".freeze
  KIND_REMOVED = "removed".freeze
  KIND_DEPLOYED = "deployed".freeze
  KIND_STATUS_CHANGED = "status_changed".freeze
  KIND_RENAMED = "renamed".freeze
  # A setting moved, such as the number of WAF custom rules. detail names the setting.
  KIND_CONFIGURED = "configured".freeze
  KINDS = [ KIND_APPEARED, KIND_REMOVED, KIND_DEPLOYED, KIND_STATUS_CHANGED, KIND_RENAMED, KIND_CONFIGURED ].freeze

  belongs_to :workspace
  belongs_to :resource, class_name: "ResourceMap::Resource"

  validates :kind, inclusion: { in: KINDS }

  scope :newest_first, -> { order(happened_at: :desc) }
  scope :since, ->(time) { where(happened_at: time..) }

  # What changed and when, in the words the map page uses.
  def line = "#{words} at #{happened_at.utc.iso8601}"

  # What changed, without when.
  def words
    name = resource.name
    case kind
    when KIND_APPEARED then "#{name} appeared"
    when KIND_REMOVED then "#{name} is gone"
    when KIND_DEPLOYED then "#{name} deployed #{to_value.present? ? to_value.first(7) : 'a new build'}"
    when KIND_RENAMED then "#{from_value || 'A resource'} was renamed #{to_value || name}"
    when KIND_STATUS_CHANGED then "#{name} went from #{from_value || 'unknown'} to #{to_value || 'unknown'}"
    else "#{name}: #{detail || 'a setting'} went from #{from_value || 'unknown'} to #{to_value || 'unknown'}"
    end
  end
end
