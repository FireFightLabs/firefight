class CreateChatSafeguards < ActiveRecord::Migration[8.1]
  def change
    create_table :chat_data_repairs, id: :uuid do |t|
      t.references :chat, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.references :workspace, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.references :asker, type: :uuid, polymorphic: true
      t.string :tool_call_id, null: false
      t.string :tool_name, null: false
      t.string :action_key, null: false
      t.uuid :environment_id
      t.string :statement_kind, null: false
      t.string :table_name
      t.text :statement
      t.text :check_query
      t.string :status, null: false, default: "proposed"
      t.integer :rows_counted
      t.text :sample
      t.integer :wrong_before
      t.datetime :counted_at
      t.text :refusal
      t.integer :rows_copied
      t.text :rows_copy
      t.datetime :copied_at
      t.datetime :copy_expires_at
      t.datetime :copy_cleared_at
      t.integer :wrong_after
      t.datetime :checked_at
      t.text :check_error
      t.timestamps
    end
    add_index :chat_data_repairs, [ :chat_id, :tool_call_id ], unique: true
    add_index :chat_data_repairs, :copy_expires_at, where: "rows_copy IS NOT NULL"

    create_table :chat_mitigations, id: :uuid do |t|
      t.references :chat, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.references :workspace, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.references :asker, type: :uuid, polymorphic: true
      t.string :tool_call_id, null: false
      t.string :tool_name, null: false
      t.string :action_key, null: false
      t.uuid :environment_id
      t.jsonb :arguments, null: false, default: {}
      t.string :target
      t.text :intent
      t.text :result
      t.integer :duration_minutes
      t.string :status, null: false, default: "proposed"
      t.datetime :started_at
      t.datetime :expires_at
      t.datetime :reminded_at
      t.datetime :claimed_at
      t.string :undo_state, null: false, default: "none"
      t.jsonb :undo_steps, null: false, default: []
      t.text :undo_note
      t.datetime :ended_at
      t.references :ended_by, type: :uuid, foreign_key: { to_table: :workspace_memberships, on_delete: :nullify }
      t.references :plan_step, type: :uuid, foreign_key: { to_table: :chat_plan_steps, on_delete: :nullify }
      t.text :outcome
      t.datetime :told_at
      t.string :message_channel_id
      t.string :message_id
      t.timestamps
    end
    add_index :chat_mitigations, [ :chat_id, :tool_call_id ], unique: true
    add_index :chat_mitigations, [ :status, :expires_at ]

    create_table :chat_owner_asks, id: :uuid do |t|
      t.references :chat, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.references :workspace, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.string :tool_call_id, null: false
      t.string :tool_name, null: false
      t.references :owner, type: :uuid, foreign_key: { to_table: :workspace_memberships, on_delete: :nullify }
      t.string :owner_name, null: false
      t.string :owner_role, null: false
      t.string :what, null: false
      t.string :status, null: false, default: "pending"
      t.references :confirmed_by, type: :uuid, foreign_key: { to_table: :workspace_memberships, on_delete: :nullify }
      t.datetime :asked_at
      t.datetime :answered_at
      t.string :message_channel_id
      t.string :message_id
      t.datetime :told_at
      t.timestamps
    end
    add_index :chat_owner_asks, [ :chat_id, :tool_call_id ], unique: true
  end
end
