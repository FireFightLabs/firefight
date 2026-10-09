class AddContradictedByToChatMemories < ActiveRecord::Migration[8.1]
  def change
    add_reference :chat_memories, :contradicted_by, type: :uuid, foreign_key: { to_table: :chat_memories, on_delete: :nullify }, index: true
  end
end
