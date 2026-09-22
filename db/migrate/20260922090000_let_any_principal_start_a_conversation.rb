class LetAnyPrincipalStartAConversation < ActiveRecord::Migration[8.1]
  # A chat over MCP acts as whoever the key belongs to, which may be a service key or an agent,
  # not only a person. The same shape Investigation#triggered_by already has.
  def up
    add_column :conversations, :started_by_type, :string
    execute "UPDATE conversations SET started_by_type = 'WorkspaceMembership' WHERE started_by_id IS NOT NULL"
    remove_foreign_key :conversations, :workspace_memberships, column: :started_by_id
    remove_index :conversations, :started_by_id
    add_index :conversations, [ :started_by_type, :started_by_id ]
  end

  def down
    remove_index :conversations, [ :started_by_type, :started_by_id ]
    execute "DELETE FROM conversations WHERE started_by_type IS NOT NULL AND started_by_type <> 'WorkspaceMembership'"
    remove_column :conversations, :started_by_type
    add_index :conversations, :started_by_id
    add_foreign_key :conversations, :workspace_memberships, column: :started_by_id
  end
end
