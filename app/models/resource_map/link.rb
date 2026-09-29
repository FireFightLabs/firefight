# How two resources depend on each other, and how that was found. A sweep owns the links it declared or matched, a
# person or Halon owns the ones they added.
class ResourceMap::Link < ApplicationRecord
  self.table_name = "resource_map_links"

  belongs_to :workspace
  belongs_to :from_resource, class_name: "ResourceMap::Resource", inverse_of: :links_out
  belongs_to :to_resource, class_name: "ResourceMap::Resource", inverse_of: :links_in
  belongs_to :integration_environment, optional: true

  validates :relation, inclusion: { in: ResourceMap::RELATIONS }
  validates :origin, inclusion: { in: ResourceMap::ORIGINS }

  def suggested? = origin == ResourceMap::ORIGIN_SUGGESTED

  def sentence = "#{from_resource.name} #{ResourceMap::RELATION_WORDS.fetch(relation)} #{to_resource.name}"
end
