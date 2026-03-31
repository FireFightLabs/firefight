class SeedCatalogTypesForExistingWorkspaces < ActiveRecord::Migration[8.1]
  def up
    Workspace.find_each do |workspace|
      next if workspace.catalog_types.exists?

      workspace.setup_catalogue!
    end
  end

  def down
    CatalogEntryRelationship.delete_all
    CatalogEntry.delete_all
    CatalogAttributeDefinition.delete_all
    CatalogType.delete_all
  end
end
