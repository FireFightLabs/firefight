class AddSafeChangesWithoutAskingToWorkspaces < ActiveRecord::Migration[8.1]
  def change
    add_column :workspaces, :safe_changes_without_asking, :boolean, default: true, null: false
  end
end
