class AddTitleToConversations < ActiveRecord::Migration[8.1]
  # The first thing the person asked, so a list of chats reads without decrypting every message in
  # every one of them. Text rather than string because the value is encrypted.
  def change
    add_column :conversations, :title, :text
  end
end
