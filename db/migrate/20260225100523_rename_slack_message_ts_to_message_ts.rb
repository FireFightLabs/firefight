class RenameSlackMessageTsToMessageTs < ActiveRecord::Migration[8.0]
  def change
    rename_column :incident_actions, :slack_message_ts, :message_ts
  end
end
