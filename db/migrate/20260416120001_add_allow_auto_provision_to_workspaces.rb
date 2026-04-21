class AddAllowAutoProvisionToWorkspaces < ActiveRecord::Migration[8.1]
  def change
    add_column :workspaces, :allow_auto_provision, :boolean, null: false, default: false
  end
end
