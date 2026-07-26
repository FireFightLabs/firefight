class ScopeIntegrationSlugUniquenessToActive < ActiveRecord::Migration[8.1]
  def change
    remove_index :integrations, column: [ :workspace_id, :slug ], unique: true
    add_index :integrations, [ :workspace_id, :slug ], unique: true,
              where: "deleted_at IS NULL", name: "index_integrations_on_active_slug"
  end
end
