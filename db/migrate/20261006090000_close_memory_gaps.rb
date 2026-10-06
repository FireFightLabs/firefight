class CloseMemoryGaps < ActiveRecord::Migration[8.1]
  def change
    # What a memory was before a sweep flagged it outdated, and why, so the flag can be lifted when the cause goes away.
    add_column :chat_memories, :outdated_from, :string
    add_column :chat_memories, :outdated_cause, :string
    add_reference :chat_memories, :decided_by_postmortem, type: :uuid, foreign_key: { to_table: :postmortems, on_delete: :nullify }

    create_table :chat_memory_uses, id: :uuid do |t|
      t.references :memory, type: :uuid, null: false, foreign_key: { to_table: :chat_memories, on_delete: :cascade }, index: false
      t.string :owner_type, null: false
      t.uuid :owner_id, null: false
      t.datetime :created_at, null: false
      t.index %i[memory_id owner_type owner_id], unique: true, name: "index_chat_memory_uses_once_per_owner"
    end

    create_table :chat_memory_posts, id: :uuid do |t|
      t.references :workspace, type: :uuid, null: false, foreign_key: true
      t.references :incident, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.string :kind, null: false
      t.string :channel_id, null: false
      t.string :thread_id
      t.string :message_id
      t.uuid :memory_ids, array: true, null: false, default: []
      t.timestamps
    end

    # Text because the value is encrypted.
    add_column :investigations, :seed_notes, :text
    add_column :workspaces, :memory_expiry_days, :integer
  end
end
