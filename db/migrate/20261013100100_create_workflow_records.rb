class CreateWorkflowRecords < ActiveRecord::Migration[8.1]
  def change
    create_table :workflows, id: :uuid do |t|
      t.references :workspace, type: :uuid, null: false, foreign_key: true, index: false
      t.string :name, null: false
      t.string :slug, null: false
      t.string :aliases, array: true, null: false, default: []
      t.text :description
      t.references :owner_team, type: :uuid, foreign_key: { to_table: :catalog_entries, on_delete: :nullify }
      t.boolean :enabled, null: false, default: true
      t.references :agent, type: :uuid, foreign_key: { on_delete: :nullify }
      t.uuid :live_version_id
      t.integer :cost_cap_cents
      t.references :created_by, type: :uuid, foreign_key: { to_table: :workspace_memberships, on_delete: :nullify }
      t.timestamps
      t.index [ :workspace_id, :slug ], unique: true
    end

    create_table :workflow_versions, id: :uuid do |t|
      t.references :workflow, type: :uuid, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.integer :number, null: false
      t.string :status, null: false, default: "draft"
      t.jsonb :trigger, null: false, default: {}
      t.jsonb :steps, null: false, default: []
      t.jsonb :edges, null: false, default: []
      t.jsonb :outputs, null: false, default: {}
      t.integer :revision, null: false, default: 0
      t.string :author_kind, null: false
      t.references :author, type: :uuid, foreign_key: { to_table: :workspace_memberships, on_delete: :nullify }
      t.text :reason
      t.references :parent_version, type: :uuid, foreign_key: { to_table: :workflow_versions, on_delete: :nullify }
      t.datetime :published_at
      t.references :published_by, type: :uuid, foreign_key: { to_table: :workspace_memberships, on_delete: :nullify }
      t.timestamps
      t.index [ :workflow_id, :number ], unique: true
      t.index :workflow_id, unique: true, where: "status = 'draft'", name: "index_workflow_versions_one_draft"
      t.index :workflow_id, unique: true, where: "status = 'live'", name: "index_workflow_versions_one_live"
    end
    add_foreign_key :workflows, :workflow_versions, column: :live_version_id, on_delete: :nullify
    add_index :workflows, :live_version_id

    create_table :workflow_runs, id: :uuid do |t|
      t.references :workspace, type: :uuid, null: false, foreign_key: true, index: false
      t.references :workflow, type: :uuid, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :version, type: :uuid, null: false, foreign_key: { to_table: :workflow_versions }
      t.references :parent_run, type: :uuid, foreign_key: { to_table: :workflow_runs, on_delete: :nullify }
      t.string :parent_step_key
      t.string :status, null: false, default: "queued"
      t.string :trigger_kind, null: false
      t.jsonb :trigger_payload, null: false, default: {}
      t.jsonb :inputs, null: false, default: {}
      t.jsonb :outputs
      t.string :start_key, null: false
      t.references :agent, type: :uuid, foreign_key: { on_delete: :nullify }
      t.string :started_by_kind, null: false
      t.references :started_by, type: :uuid, foreign_key: { to_table: :workspace_memberships, on_delete: :nullify }
      t.text :error
      t.datetime :started_at
      t.datetime :finished_at
      t.timestamps
      t.index [ :workflow_id, :start_key ], unique: true
      t.index [ :workflow_id, :created_at ]
      t.index [ :workspace_id, :created_at ]
      t.index :status
    end

    create_table :workflow_run_steps, id: :uuid do |t|
      t.references :run, type: :uuid, null: false, foreign_key: { to_table: :workflow_runs, on_delete: :cascade }, index: false
      t.string :step_key, null: false
      t.string :iteration, null: false, default: ""
      t.string :name
      t.string :kind
      t.string :status, null: false
      t.string :route
      t.jsonb :input
      t.jsonb :output
      t.uuid :saved_result_ids, array: true, null: false, default: []
      t.integer :attempts, null: false, default: 0
      t.text :error
      t.datetime :started_at
      t.datetime :finished_at
      t.timestamps
      t.index [ :run_id, :step_key, :iteration ], unique: true
    end

    create_table :workflow_edits, id: :uuid do |t|
      t.references :workflow, type: :uuid, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :version, type: :uuid, foreign_key: { to_table: :workflow_versions, on_delete: :cascade }, index: false
      t.string :operation, null: false
      t.jsonb :payload, null: false, default: {}
      t.string :targets, array: true, null: false, default: []
      t.string :status, null: false
      t.string :author_kind, null: false
      t.references :author, type: :uuid, foreign_key: { to_table: :workspace_memberships, on_delete: :nullify }
      t.text :reason
      t.integer :base_revision
      t.integer :applied_revision
      t.uuid :change_set_id
      t.references :source_run, type: :uuid, foreign_key: { to_table: :workflow_runs, on_delete: :nullify }
      t.references :source_chat, type: :uuid, foreign_key: { to_table: :chats, on_delete: :nullify }
      t.references :decided_by, type: :uuid, foreign_key: { to_table: :workspace_memberships, on_delete: :nullify }
      t.datetime :decided_at
      t.timestamps
      t.index [ :workflow_id, :status ]
      t.index [ :version_id, :applied_revision ]
      t.index :change_set_id
    end

    change_column_null :chat_saved_results, :chat_id, true
    add_reference :chat_saved_results, :workflow_run, type: :uuid, foreign_key: { on_delete: :cascade }, index: false
    add_index :chat_saved_results, [ :workflow_run_id, :handle ], unique: true, where: "workflow_run_id IS NOT NULL"
    add_check_constraint :chat_saved_results, "num_nonnulls(chat_id, workflow_run_id) = 1", name: "chat_saved_results_one_owner"

    add_column :workspaces, :halon_applies_workflow_read_fixes, :boolean, null: false, default: false
  end
end
