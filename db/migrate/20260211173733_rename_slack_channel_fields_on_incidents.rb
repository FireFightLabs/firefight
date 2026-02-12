class RenameSlackChannelFieldsOnIncidents < ActiveRecord::Migration[8.1]
  def change
    rename_column :incidents, :slack_channel_id, :channel_id
    rename_column :incidents, :slack_channel_name, :channel_name
  end
end
