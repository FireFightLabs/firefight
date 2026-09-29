class AddRejectedByToChatMemories < ActiveRecord::Migration[8.1]
  def change
    add_reference :chat_memories, :rejected_by, type: :uuid, foreign_key: { to_table: :workspace_memberships, on_delete: :nullify }
    add_column :chat_memories, :rejected_at, :datetime
  end
end
