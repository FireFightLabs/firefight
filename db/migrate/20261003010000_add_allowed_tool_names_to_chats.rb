class AddAllowedToolNamesToChats < ActiveRecord::Migration[8.1]
  def change
    # Tools the person allowed for the rest of the chat, so a call to one stops waiting for a confirmation.
    add_column :chats, :allowed_tool_names, :jsonb, default: [], null: false
  end
end
