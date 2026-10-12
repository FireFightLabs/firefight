# A note written in the platform is in the platform's own markup, which the dashboard shows as the platform reads it.
# One added on the dashboard is shown exactly as typed, and nothing else on the row tells the two apart.
class AddFromPlatformToChatQueuedMessages < ActiveRecord::Migration[8.1]
  def change
    add_column :chat_queued_messages, :from_platform, :boolean, null: false, default: false
  end
end
