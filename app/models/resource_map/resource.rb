# One thing a connection reaches: a service, a database, a repository. Removed ones are kept, so a resource that comes
# back keeps its links and when it was first seen.
class ResourceMap::Resource < ApplicationRecord
  self.table_name = "resource_map_resources"

  belongs_to :workspace
  belongs_to :integration_environment, optional: true
  has_many :links_out, class_name: "ResourceMap::Link", foreign_key: :from_resource_id, inverse_of: :from_resource, dependent: :delete_all
  has_many :links_in, class_name: "ResourceMap::Link", foreign_key: :to_resource_id, inverse_of: :to_resource, dependent: :delete_all
  has_many :changes_seen, class_name: "ResourceMap::Change", foreign_key: :resource_id, inverse_of: :resource, dependent: :delete_all
  has_many :entry_links, class_name: "ResourceMap::EntryLink", foreign_key: :resource_id, inverse_of: :resource, dependent: :delete_all
  has_many :catalog_entries, through: :entry_links

  validates :provider, :account, :external_id, :name, presence: true
  validates :kind, inclusion: { in: ResourceMap::KINDS }

  scope :present, -> { where(removed_at: nil) }

  NEIGHBORHOOD_DEPTH = 2
  NEIGHBORHOOD_LIMIT = 100

  # A resource named the way a person or Halon would, by its name or its provider's id, still present ones first.
  def self.named(workspace, reference)
    wanted = reference.to_s.strip.downcase
    return none if wanted.empty?

    where(workspace: workspace).where("lower(name) = :wanted OR lower(external_id) = :wanted", wanted: wanted)
      .order(Arel.sql("removed_at IS NOT NULL"), :provider, :account, :kind)
  end

  # Every link within depth hops of this resource, in either direction, each with the hop it was found at.
  def neighborhood(depth: NEIGHBORHOOD_DEPTH)
    hops = { id => 0 }
    frontier = [ id ]
    found = {}
    depth.times do |hop|
      links = ResourceMap::Link.standing.where(from_resource_id: frontier).or(ResourceMap::Link.standing.where(to_resource_id: frontier))
                               .includes(:from_resource, :to_resource, integration_environment: :integration).limit(NEIGHBORHOOD_LIMIT)
      frontier = links.flat_map do |link|
        found[link.id] ||= [ link, hop + 1 ]
        [ link.from_resource_id, link.to_resource_id ].reject { |each| hops.key?(each) }.each { |each| hops[each] = hop + 1 }
      end.uniq
      break if frontier.empty? || found.size >= NEIGHBORHOOD_LIMIT
    end
    found.values.first(NEIGHBORHOOD_LIMIT)
  end
end
