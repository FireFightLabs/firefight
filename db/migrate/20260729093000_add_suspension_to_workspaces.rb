class AddSuspensionToWorkspaces < ActiveRecord::Migration[8.1]
  def change
    add_column :workspaces, :suspended_at, :datetime
    add_column :workspaces, :suspended_reason, :string
  end
end
