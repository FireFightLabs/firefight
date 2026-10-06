class IndexResourceMapForQueries < ActiveRecord::Migration[8.1]
  PRESENT = "removed_at IS NULL".freeze
  STANDING = "dismissed_at IS NULL".freeze

  def change
    add_index :resource_map_resources, %i[workspace_id kind], where: PRESENT, name: "index_resource_map_resources_present_kind"
    add_index :resource_map_resources, %i[workspace_id provider account], where: PRESENT, name: "index_resource_map_resources_present_account"
    # Statuses are stored as the provider wrote them, and health reads them case-blind, so the index does too.
    add_index :resource_map_resources, "workspace_id, lower(status)", where: PRESENT, name: "index_resource_map_resources_present_status"
    # The C collation lets one index serve both a name prefix (LIKE 'web%') and paging in name order.
    add_index :resource_map_resources, 'workspace_id, lower(name) COLLATE "C", id', where: PRESENT, name: "index_resource_map_resources_present_name"
    add_index :resource_map_resources, :details, using: :gin, opclass: :jsonb_path_ops, name: "index_resource_map_resources_details"

    add_index :resource_map_links, %i[to_resource_id relation], where: STANDING, name: "index_resource_map_links_standing_in"
    add_index :resource_map_links, %i[from_resource_id relation], where: STANDING, name: "index_resource_map_links_standing_out"
  end
end
