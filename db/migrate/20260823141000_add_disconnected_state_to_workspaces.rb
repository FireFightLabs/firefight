class AddDisconnectedStateToWorkspaces < ActiveRecord::Migration[8.1]
  def change
    add_column :workspaces, :disconnected_at, :datetime
    add_column :workspaces, :disconnected_reason, :string
  end
end
