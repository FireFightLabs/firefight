class CreateChatPlans < ActiveRecord::Migration[8.1]
  def change
    create_table :chat_plans, id: :uuid do |t|
      t.references :chat, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.references :workspace, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.references :made_by, type: :uuid, polymorphic: true
      t.text :goal, null: false
      t.string :status, null: false, default: "active"
      t.datetime :run_at
      t.string :time_zone
      t.references :approved_by, type: :uuid, foreign_key: { to_table: :workspace_memberships, on_delete: :nullify }
      t.datetime :approved_at
      t.datetime :started_at
      t.datetime :finished_at
      t.text :stop_reason
      t.text :outcome
      t.text :next_step
      t.jsonb :links, null: false, default: []
      t.text :state_now
      t.string :state_change
      t.datetime :state_checked_at
      t.references :undoes, type: :uuid, foreign_key: { to_table: :chat_plans, on_delete: :nullify }
      t.datetime :undo_requested_at
      t.string :message_channel_id
      t.string :message_id
      t.datetime :moved_at, null: false
      t.timestamps
    end
    add_index :chat_plans, [ :status, :run_at ]

    create_table :chat_plan_steps, id: :uuid do |t|
      t.references :plan, type: :uuid, null: false, index: false, foreign_key: { to_table: :chat_plans, on_delete: :cascade }
      t.integer :position, null: false
      t.string :kind, null: false
      t.text :description, null: false
      t.string :place
      t.string :tool
      t.text :undo
      t.string :status, null: false, default: "not_started"
      t.text :note
      t.string :verdict
      t.jsonb :links, null: false, default: []
      t.datetime :started_at
      t.datetime :finished_at
      t.timestamps
    end
    add_index :chat_plan_steps, [ :plan_id, :position ], unique: true
  end
end
