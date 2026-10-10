class CreateChatHelpers < ActiveRecord::Migration[8.1]
  def change
    create_table :chat_helpers, id: :uuid do |t|
      t.references :chat, type: :uuid, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :workspace, type: :uuid, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.string :tool_call_id, null: false
      t.integer :position, null: false
      t.string :title, null: false
      t.text :brief, null: false
      t.boolean :deep, null: false, default: false
      t.string :status, null: false, default: "running"
      t.string :model
      t.integer :turns_used, null: false, default: 0
      t.bigint :spent_micros, null: false, default: 0
      t.text :report
      t.text :ended_because
      t.datetime :started_at, null: false
      t.datetime :finished_at
      t.timestamps
    end
    add_index :chat_helpers, [ :chat_id, :tool_call_id, :position ], unique: true
    add_index :chat_helpers, [ :workspace_id, :status ]
  end
end
