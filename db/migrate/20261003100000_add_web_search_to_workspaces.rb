class AddWebSearchToWorkspaces < ActiveRecord::Migration[8.1]
  def change
    add_column :workspaces, :web_search_enabled, :boolean, default: true, null: false
    add_column :code_agent_sessions, :web_lookups, :integer, default: 0, null: false
  end
end
