# Every other message reference is message_ts. This one named the platform,
# which only mattered while the write lived in a Slack handler. It is a
# cross-platform service now.
class RenameShoutoutSlackMessageTs < ActiveRecord::Migration[8.1]
  def change
    rename_column :shoutouts, :slack_message_ts, :message_ts
  end
end
