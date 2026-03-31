class MakeCatalogSlugUniqueOnlyActive < ActiveRecord::Migration[8.1]
  def change
    remove_index :catalog_entries, [ :catalog_type_id, :slug ]
    add_index :catalog_entries, [ :catalog_type_id, :slug ], unique: true,
      where: "deleted_at IS NULL",
      name: "index_catalog_entries_on_type_and_slug_active"

    remove_index :catalog_types, [ :workspace_id, :slug ]
    add_index :catalog_types, [ :workspace_id, :slug ], unique: true,
      where: "deleted_at IS NULL",
      name: "index_catalog_types_on_workspace_and_slug_active"
  end
end
