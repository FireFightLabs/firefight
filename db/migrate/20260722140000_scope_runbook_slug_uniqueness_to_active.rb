class ScopeRunbookSlugUniquenessToActive < ActiveRecord::Migration[8.1]
  def change
    remove_index :runbooks, column: [ :workspace_id, :slug ], unique: true,
                 name: "index_runbooks_on_workspace_id_and_slug"
    add_index :runbooks, [ :workspace_id, :slug ], unique: true,
              where: "deleted_at IS NULL", name: "index_runbooks_on_workspace_id_and_slug_active"
  end
end
