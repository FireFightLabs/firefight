# Where a thread's confirmation was posted, so it can be redrawn when the person moves past it, when a lost reply was
# run again, so it is run again at most once, and the answer a turn is writing in its thread and whether anything has
# shown in it yet, so a lost turn's answer can be ended where it stopped.
class AddReplyRecoveryToConversations < ActiveRecord::Migration[8.1]
  def change
    add_column :conversations, :confirmation_message_id, :string
    add_column :conversations, :reply_recovered_at, :datetime
    add_column :conversations, :answer_message_id, :string
    add_column :conversations, :answer_shown, :boolean, default: false, null: false
  end
end
