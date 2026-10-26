# Halon checks what the workspace remembers against production every night, merges memories that say the same thing,
# and learns from every chat once it goes quiet. A memory keeps when Halon last tried it and what came of it, whether
# Halon made its last decision, and every change to it as history. A night's check is one row, the subject of the run
# that does it, and a chat keeps how far Halon has read it for lessons.
class LetHalonCheckMemories < ActiveRecord::Migration[8.1]
  def change
    change_table :chat_memories, bulk: true do |t|
      t.datetime :checked_at
      t.string :check_outcome
      t.boolean :decided_by_halon, null: false, default: false
    end
    add_index :chat_memories, [ :workspace_id, :checked_at ]

    create_table :chat_memory_events, id: :uuid do |t|
      t.references :workspace, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.references :memory, type: :uuid, null: false, index: false, foreign_key: { to_table: :chat_memories, on_delete: :cascade }
      t.string :kind, null: false
      t.string :actor
      t.references :member, type: :uuid, foreign_key: { to_table: :workspace_memberships, on_delete: :nullify }
      t.text :detail
      t.datetime :created_at, null: false
    end
    add_index :chat_memory_events, [ :memory_id, :created_at ]

    create_table :chat_memory_reviews, id: :uuid do |t|
      t.references :workspace, type: :uuid, null: false, index: false, foreign_key: { on_delete: :cascade }
      t.date :reviewed_on, null: false
      t.uuid :memory_ids, array: true, null: false, default: []
      t.uuid :settled_ids, array: true, null: false, default: []
      t.integer :removal_cap, null: false
      t.integer :removals, null: false, default: 0
      t.integer :merged, null: false, default: 0
      t.datetime :finished_at
      t.timestamps
    end
    add_index :chat_memory_reviews, [ :workspace_id, :reviewed_on ], unique: true

    add_column :conversations, :learned_through_at, :datetime
  end
end
