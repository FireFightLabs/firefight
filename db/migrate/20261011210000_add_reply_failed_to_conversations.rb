# A turn that gave up says so in the chat like an answer, so an outside agent waiting on it needs the row to tell the two
# apart.
class AddReplyFailedToConversations < ActiveRecord::Migration[8.1]
  def change
    add_column :conversations, :reply_failed, :boolean, default: false, null: false
  end
end
