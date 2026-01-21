class AddIncidentsChannelToWorkspace < ActiveRecord::Migration[8.1]
  def change
    add_column :workspaces, :incidents_channel_id, :string
    add_index :workspaces, :incidents_channel_id
  end
end
