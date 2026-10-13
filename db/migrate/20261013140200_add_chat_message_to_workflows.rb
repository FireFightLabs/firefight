class AddChatMessageToWorkflows < ActiveRecord::Migration[8.1]
  def change
    change_table :workflows, bulk: true do |t|
      # The message a workflow made from a chat in a thread keeps there, redrawn as it moves.
      t.string :chat_message_channel_id
      t.string :chat_message_id
    end
  end
end
