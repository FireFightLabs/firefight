# Where a thread's confirmation was posted, so it can be redrawn when the person moves past it, and when a lost reply was
# run again, so it is run again at most once.
class AddReplyRecoveryToConversations < ActiveRecord::Migration[8.1]
  def change
    add_column :conversations, :confirmation_message_id, :string
    add_column :conversations, :reply_recovered_at, :datetime
  end
end
