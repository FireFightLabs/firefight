# A catalog entry pointing at a resource it runs on, so who owns it (the catalog) and where it runs (the map) meet.
class ResourceMap::EntryLink < ApplicationRecord
  self.table_name = "resource_map_entry_links"

  belongs_to :workspace
  belongs_to :catalog_entry
  belongs_to :resource, class_name: "ResourceMap::Resource"
  belongs_to :added_by, class_name: "WorkspaceMembership", optional: true

  validates :resource_id, uniqueness: { scope: :catalog_entry_id }

  # A resource is found by the services it runs and their owners.
  after_commit -> { SearchDocument.index_later(ResourceMap::Resource, [ resource_id ]) }, on: [ :create, :destroy ]
end
