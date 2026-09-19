class AddTitleToConversations < ActiveRecord::Migration[8.1]
  # Text because the value is encrypted.
  def change
    add_column :conversations, :title, :text
  end
end
