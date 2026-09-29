class CreateChatMemories < ActiveRecord::Migration[8.1]
  def change
    create_table :chat_memories, id: :uuid do |t|
      t.references :workspace, type: :uuid, null: false, foreign_key: true, index: false
      t.text :text, null: false
      t.string :state, null: false
      t.references :subject, type: :uuid, polymorphic: true
      t.references :source, type: :uuid, polymorphic: true
      t.references :added_by, type: :uuid, foreign_key: { to_table: :workspace_memberships, on_delete: :nullify }
      t.datetime :confirmed_at
      t.references :confirmed_by, type: :uuid, foreign_key: { to_table: :workspace_memberships, on_delete: :nullify }
      t.text :state_reason
      t.references :replaced_by, type: :uuid, foreign_key: { to_table: :chat_memories, on_delete: :nullify }
      t.datetime :last_used_at
      t.integer :use_count, null: false, default: 0
      t.timestamps
    end
    add_index :chat_memories, %i[workspace_id state]
  end
end
