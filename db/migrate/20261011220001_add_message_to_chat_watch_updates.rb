# A watch update sent to someone's direct messages keeps where it was posted, so a reply to it is answered knowing which
# watch it came from.
class AddMessageToChatWatchUpdates < ActiveRecord::Migration[8.1]
  def change
    add_column :chat_watch_updates, :message_channel_id, :string
    add_column :chat_watch_updates, :message_id, :string
    add_index :chat_watch_updates, %i[message_channel_id message_id]
  end
end
