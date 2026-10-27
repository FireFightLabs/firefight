# A lesson an incident taught is checked in pull request reviews only once its incident lead or a workspace admin
# approves it, and a strict one fails a check on the pull request rather than only commenting.
class AddLessonApprovalToChatMemories < ActiveRecord::Migration[8.1]
  def change
    add_reference :chat_memories, :approved_by, type: :uuid, foreign_key: { to_table: :workspace_memberships, on_delete: :nullify }
    add_column :chat_memories, :approved_at, :datetime
    add_column :chat_memories, :strict, :boolean, default: false, null: false
    add_index :chat_memories, :workspace_id, where: "approved_at IS NOT NULL", name: "index_chat_memories_approved_lessons"
  end
end
