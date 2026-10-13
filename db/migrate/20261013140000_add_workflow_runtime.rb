class AddWorkflowRuntime < ActiveRecord::Migration[8.1]
  def change
    change_table :workflows, bulk: true do |t|
      t.datetime :next_run_at
      t.string :freeze_behaviour, null: false, default: "stop"
      t.integer :runs_per_hour, null: false, default: 60
      t.string :subject_key
      t.boolean :all_clear, null: false, default: false
      t.references :origin_conversation, type: :uuid, foreign_key: { to_table: :conversations, on_delete: :nullify }
      t.text :trigger_refusal
      t.datetime :trigger_refused_at
      t.index :next_run_at, where: "next_run_at IS NOT NULL"
    end

    change_table :workflow_runs, bulk: true do |t|
      t.boolean :test, null: false, default: false
      t.string :real_step_keys, array: true, null: false, default: []
      t.string :subject_key
      t.datetime :told_at
      t.index [ :workflow_id, :subject_key ], unique: true, name: "index_workflow_runs_one_live_per_subject",
                                              where: "subject_key IS NOT NULL AND status IN ('queued', 'running', 'waiting', 'paused')"
    end

    add_column :workflow_run_steps, :invocation_ids, :uuid, array: true, null: false, default: []
    add_reference :ability_invocations, :workflow_run, type: :uuid, foreign_key: { on_delete: :nullify }
    add_reference :ability_approvals, :workflow_run, type: :uuid, foreign_key: { on_delete: :nullify }

    add_reference :investigation_notices, :workflow_run, type: :uuid, foreign_key: { on_delete: :nullify }

    add_column :workspaces, :workflow_event_runs_per_hour, :integer, null: false, default: 100

    create_table :workflow_publish_requests, id: :uuid do |t|
      t.references :workspace, type: :uuid, null: false, foreign_key: true, index: false
      t.references :workflow, type: :uuid, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :version, type: :uuid, null: false, foreign_key: { to_table: :workflow_versions, on_delete: :cascade }
      t.references :requester, type: :uuid, null: false, foreign_key: { to_table: :workspace_memberships, on_delete: :cascade }
      t.datetime :requested_at
      t.datetime :published_at
      t.references :published_by, type: :uuid, foreign_key: { to_table: :workspace_memberships, on_delete: :nullify }
      t.datetime :dismissed_at
      t.jsonb :notifications, null: false, default: []
      t.timestamps
      t.index [ :workflow_id, :requester_id ], unique: true
      t.index [ :workspace_id, :requested_at ]
    end
  end
end
