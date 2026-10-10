# The provider a workspace's code boxes are held to, empty for the deployment's own main and backup.
class AddSandboxProviderToWorkspaces < ActiveRecord::Migration[8.1]
  def change
    add_column :workspaces, :sandbox_provider, :string
  end
end
