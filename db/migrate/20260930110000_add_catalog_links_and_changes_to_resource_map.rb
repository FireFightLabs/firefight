class AddCatalogLinksAndChangesToResourceMap < ActiveRecord::Migration[8.1]
  def change
    create_table :resource_map_entry_links, id: :uuid do |t|
      t.references :workspace, type: :uuid, null: false, foreign_key: true, index: false
      t.references :catalog_entry, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.references :resource, type: :uuid, null: false, foreign_key: { to_table: :resource_map_resources, on_delete: :cascade }
      t.references :added_by, type: :uuid, foreign_key: { to_table: :workspace_memberships, on_delete: :nullify }
      t.timestamps
    end
    add_index :resource_map_entry_links, %i[catalog_entry_id resource_id], unique: true, name: "index_resource_map_entry_links_identity"
    add_index :resource_map_entry_links, :workspace_id

    create_table :resource_map_changes, id: :uuid do |t|
      t.references :workspace, type: :uuid, null: false, foreign_key: true, index: false
      t.references :resource, type: :uuid, null: false, foreign_key: { to_table: :resource_map_resources, on_delete: :cascade }, index: false
      t.string :kind, null: false
      t.string :from_value
      t.string :to_value
      t.datetime :happened_at, null: false
      t.timestamps
    end
    add_index :resource_map_changes, %i[resource_id happened_at]
    add_index :resource_map_changes, %i[workspace_id happened_at]

    change_table :resource_map_links, bulk: true do |t|
      t.text :note
      t.references :added_by, type: :uuid, foreign_key: { to_table: :workspace_memberships, on_delete: :nullify }
      t.datetime :confirmed_at
      t.references :confirmed_by, type: :uuid, foreign_key: { to_table: :workspace_memberships, on_delete: :nullify }
      t.datetime :dismissed_at
    end
  end
end
