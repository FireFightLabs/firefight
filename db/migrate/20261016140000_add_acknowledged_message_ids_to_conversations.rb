class AddAcknowledgedMessageIdsToConversations < ActiveRecord::Migration[8.1]
  def change
    add_column :conversations, :acknowledged_message_ids, :string, array: true, default: [], null: false
  end
end
