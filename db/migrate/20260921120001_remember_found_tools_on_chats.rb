class RememberFoundToolsOnChats < ActiveRecord::Migration[8.1]
  # In the order they were found, so they are handed back in the same order every turn.
  def change
    add_column :chats, :found_tool_names, :jsonb, null: false, default: []
  end
end
