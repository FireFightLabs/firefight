class CreateCodeAgentSessions < ActiveRecord::Migration[8.1]
  def change
    create_table :code_agent_sessions, id: :uuid do |t|
      t.references :workspace, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.string :token_digest, null: false, index: { unique: true }
      t.string :provider, null: false
      t.string :model, null: false
      t.bigint :budget_micros, null: false
      t.bigint :spent_micros, null: false, default: 0
      t.integer :calls_running, null: false, default: 0
      t.string :repository, null: false
      t.datetime :expires_at, null: false
      t.datetime :closed_at
      t.timestamps
    end
  end
end
