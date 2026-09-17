class AddPinnedAndArchivedToConversations < ActiveRecord::Migration[8.1]
  # When, not whether, so a list can order by how recently a chat was pinned.
  def change
    add_column :conversations, :pinned_at, :datetime
    add_column :conversations, :archived_at, :datetime
  end
end
