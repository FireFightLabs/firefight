class CreateConversations < ActiveRecord::Migration[8.1]
  def change
    create_table :conversations, id: :uuid do |t|
      t.references :workspace, type: :uuid, null: false, foreign_key: true
      # Polymorphic, because a conversation may be about an incident or about nothing in particular.
      t.references :subject, type: :uuid, polymorphic: true
      t.references :started_by, type: :uuid, foreign_key: { to_table: :workspace_memberships }
      t.string :kind, null: false
      t.string :channel_id
      t.string :thread_id
      t.integer :max_turns, null: false
      t.integer :max_spend_cents, null: false
      t.integer :turns_used, null: false, default: 0
      t.integer :spent_cents, null: false, default: 0
      t.timestamps
    end
    # One conversation per thread, so a second mention joins rather than starting over.
    add_index :conversations, [ :workspace_id, :channel_id, :thread_id ], unique: true,
              name: "index_conversations_on_thread"
  end
end
