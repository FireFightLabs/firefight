# One thing a connection reaches: a service, a database, a repository. Removed ones are kept, so a resource that comes
# back keeps its links and when it was first seen.
class ResourceMap::Resource < ApplicationRecord
  self.table_name = "resource_map_resources"

  belongs_to :workspace
  belongs_to :integration_environment, optional: true
  has_many :links_out, class_name: "ResourceMap::Link", foreign_key: :from_resource_id, inverse_of: :from_resource, dependent: :delete_all
  has_many :links_in, class_name: "ResourceMap::Link", foreign_key: :to_resource_id, inverse_of: :to_resource, dependent: :delete_all

  validates :provider, :account, :external_id, :name, presence: true
  validates :kind, inclusion: { in: ResourceMap::KINDS }

  scope :present, -> { where(removed_at: nil) }
end
