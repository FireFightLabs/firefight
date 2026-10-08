class CreateCodeAgentSessionPauses < ActiveRecord::Migration[8.1]
  def change
    create_table :code_agent_session_pauses, id: :uuid do |t|
      t.references :session, type: :uuid, null: false, foreign_key: { to_table: :code_agent_sessions }
      t.references :workspace, type: :uuid, null: false, foreign_key: true
      t.references :conversation, type: :uuid, foreign_key: true
      t.references :decided_by, type: :uuid, foreign_key: { to_table: :workspace_memberships }
      t.string :status, null: false, default: "offered"
      t.text :arguments, null: false
      t.string :repository, null: false
      t.string :base, null: false
      t.string :target_branch
      t.string :target_sha
      t.string :saved_branch
      t.string :saved_commit
      t.string :copy_ref, null: false
      t.string :agent_session_id
      t.string :box_key
      t.bigint :budget_micros, null: false
      t.datetime :resumable_until, null: false
      t.datetime :decided_at
      t.string :message_channel_id
      t.string :message_id
      t.datetime :told_at
      t.timestamps
    end
  end
end
