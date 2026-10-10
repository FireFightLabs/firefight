# Who a box was started for, as the box itself says. No foreign key, since it is read from the provider and can name a
# workspace that is gone.
class AddOwnerToProviderSandboxes < ActiveRecord::Migration[8.1]
  def change
    add_column :provider_sandboxes, :owner_workspace_id, :uuid
    add_column :provider_sandboxes, :owner_key, :string
  end
end
