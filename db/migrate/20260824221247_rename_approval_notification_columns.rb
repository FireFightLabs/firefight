class RenameApprovalNotificationColumns < ActiveRecord::Migration[8.1]
  # Which platform the request was posted to belongs to the adapter, not the column name.
  def change
    rename_column :ability_approvals, :slack_channel_id, :notification_channel_id
    rename_column :ability_approvals, :slack_message_ts, :notification_message_id
  end
end
