class CreateConversationBench < ActiveRecord::Migration[8.1]
  def change
    create_table :conversation_bench_runs, id: :uuid do |t|
      t.string :kind, null: false
      t.string :trigger, null: false
      t.string :status, null: false, default: "running"
      t.string :prompt_version, null: false
      t.string :model, null: false
      t.string :provider
      t.string :label
      t.references :started_by, type: :uuid, foreign_key: { to_table: :users, on_delete: :nullify }
      t.datetime :finished_at
      t.timestamps
    end
    add_index :conversation_bench_runs, %i[kind created_at]

    create_table :conversation_bench_results, id: :uuid do |t|
      t.references :bench_run, type: :uuid, null: false, foreign_key: { to_table: :conversation_bench_runs, on_delete: :cascade }
      t.references :workspace, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.references :replay_of, type: :uuid, foreign_key: { to_table: :conversations, on_delete: :nullify }
      t.string :scenario, null: false
      t.string :title, null: false
      t.string :status, null: false, default: "pending"
      t.float :right
      t.float :moved_forward
      t.float :asked_when_needed
      t.float :cost
      t.float :total
      t.bigint :spent_micros, null: false, default: 0
      t.integer :turns, null: false, default: 0
      t.integer :calls, null: false, default: 0
      t.integer :not_recorded, null: false, default: 0
      t.integer :confirmations, null: false, default: 0
      t.integer :unneeded_asks, null: false, default: 0
      t.text :answer
      t.text :reason
      t.jsonb :notes, null: false, default: []
      t.datetime :started_at
      t.datetime :finished_at
      t.timestamps
    end
    add_index :conversation_bench_results, %i[bench_run_id scenario], unique: true
  end
end
