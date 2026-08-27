class AddArchiveSettingsToWorkspaces < ActiveRecord::Migration[8.1]
  def change
    add_column :workspaces, :archive_channel_enabled, :boolean, default: true, null: false
    add_column :workspaces, :archive_channel_delay_minutes, :integer, default: 60, null: false
  end
end
