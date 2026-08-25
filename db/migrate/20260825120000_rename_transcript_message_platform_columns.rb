class RenameTranscriptMessagePlatformColumns < ActiveRecord::Migration[8.1]
  def change
    rename_column :incident_transcript_messages, :slack_ts, :message_id
    rename_column :incident_transcript_messages, :slack_thread_ts, :thread_id
    rename_column :incident_transcript_messages, :slack_user_id, :platform_user_id
    rename_index :incident_transcript_messages,
                 "index_transcript_messages_on_workspace_incident_slack_ts",
                 "index_transcript_messages_on_workspace_incident_message_id"
  end
end
