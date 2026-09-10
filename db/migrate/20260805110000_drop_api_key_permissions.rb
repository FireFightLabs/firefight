class DropApiKeyPermissions < ActiveRecord::Migration[8.1]
  # Grants are what every check reads. This column was a copy that reconciled away grants made elsewhere.
  def up
    remove_column :api_keys, :permissions
  end

  def down
    add_column :api_keys, :permissions, :jsonb, null: false, default: {}

    ApiKey.reset_column_information
    ApiKey.where(workspace_membership_id: nil).find_each do |key|
      key.update_columns(permissions: key.granted_permissions)
    end
  end
end
