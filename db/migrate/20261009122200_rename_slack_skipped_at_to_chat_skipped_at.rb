# The setup step is connecting a chat, whichever platform it is, so its column says so.
class RenameSlackSkippedAtToChatSkippedAt < ActiveRecord::Migration[8.1]
  def change
    rename_column :workspace_onboardings, :slack_skipped_at, :chat_skipped_at
  end
end
