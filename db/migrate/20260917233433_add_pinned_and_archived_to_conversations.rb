class AddPinnedAndArchivedToConversations < ActiveRecord::Migration[8.1]
  # Times, not flags, so pinned chats sort by when they were pinned.
  def change
    add_column :conversations, :pinned_at, :datetime
    add_column :conversations, :archived_at, :datetime
  end
end
