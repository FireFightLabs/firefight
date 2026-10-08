class CreateChatWatchSteps < ActiveRecord::Migration[8.1]
  def change
    create_table :chat_watch_steps, id: :uuid do |t|
      t.references :watch, type: :uuid, null: false, foreign_key: { to_table: :chat_watches, on_delete: :cascade }
      t.integer :position, null: false
      t.string :label, null: false
      t.string :capability, null: false
      t.jsonb :arguments, null: false, default: {}
      t.references :integration_environment, type: :uuid, foreign_key: { on_delete: :nullify }
      t.string :run_name
      t.string :run_ref
      t.string :followed_run_id
      t.string :run_url
      t.boolean :report_start, null: false, default: false
      t.text :done_when
      t.text :failed_when
      t.text :goal
      t.integer :usual_seconds
      t.string :status, null: false, default: "waiting"
      t.datetime :started_at
      t.datetime :finished_at
      t.datetime :started_told_at
      t.datetime :finished_told_at
      t.datetime :slow_told_at
      t.string :last_digest
      t.text :last_state
      t.text :reason
      t.timestamps
    end
    add_index :chat_watch_steps, [ :watch_id, :position ], unique: true
  end
end
