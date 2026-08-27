class AddRoleToCatalogAttributeDefinitions < ActiveRecord::Migration[8.1]
  def up
    # Which job an attribute does for alert routing (members, manager,
    # notification_channel). One attribute per role per type.
    add_column :catalog_attribute_definitions, :role, :string
    add_index :catalog_attribute_definitions, [ :catalog_type_id, :role ],
              unique: true, where: "role IS NOT NULL",
              name: "index_catalog_attribute_definitions_on_type_and_role"

    # Existing workspaces were routed through these exact slugs, so tagging
    # them keeps routing behavior identical on deploy.
    execute <<~SQL
      UPDATE catalog_attribute_definitions
      SET role = 'members'
      WHERE slug = 'members' AND attribute_type = 'workspace_members'
    SQL
    execute <<~SQL
      UPDATE catalog_attribute_definitions
      SET role = 'manager'
      WHERE slug = 'manager' AND attribute_type = 'workspace_member'
    SQL
    execute <<~SQL
      UPDATE catalog_attribute_definitions
      SET role = 'notification_channel'
      WHERE slug = 'slack_channel' AND attribute_type = 'slack_channel'
    SQL
  end

  def down
    remove_index :catalog_attribute_definitions, name: "index_catalog_attribute_definitions_on_type_and_role"
    remove_column :catalog_attribute_definitions, :role
  end
end
