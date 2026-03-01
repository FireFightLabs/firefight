class CreateSolidWorkflowTables < ActiveRecord::Migration[8.1]
  def change
    create_table :solid_workflow_workflows, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.string :name, null: false
      t.string :workflow_class, null: false
      t.string :subject_type, null: false
      t.uuid :subject_id, null: false
      t.string :state, null: false, default: "pending"
      t.jsonb :context, null: false, default: {}
      t.jsonb :workflow_config, default: {}
      t.jsonb :state_timestamps, null: false, default: {}
      t.datetime :started_at
      t.datetime :completed_at
      t.string :cancelled_by
      t.text :cancellation_reason
      t.timestamps

      t.index [ :subject_type, :subject_id ], name: "idx_sw_workflows_on_subject"
      t.index [ :subject_type, :subject_id, :state ], name: "idx_sw_workflows_on_subject_and_state"
      t.index :state
      t.index :workflow_class
      t.index :created_at
      t.index [ :state, :updated_at ], name: "idx_sw_workflows_on_state_and_updated_at"
    end

    create_table :solid_workflow_steps, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid :workflow_id, null: false
      t.string :name, null: false
      t.string :status, null: false, default: "pending"
      t.string :depends_on, array: true, default: []
      t.integer :position
      t.integer :attempts, null: false, default: 0
      t.integer :max_attempts, default: 5
      t.datetime :run_at
      t.datetime :started_at
      t.datetime :completed_at
      t.jsonb :input, null: false, default: {}
      t.jsonb :output, null: false, default: {}
      t.jsonb :retry_config
      t.text :last_error
      t.text :skip_reason
      t.timestamps

      t.index :workflow_id
      t.index [ :workflow_id, :name ], name: "idx_sw_steps_on_workflow_id_and_name"
      t.index [ :workflow_id, :status ], name: "idx_sw_steps_on_workflow_id_and_status"
      t.index :status
      t.index [ :status, :updated_at ], name: "idx_sw_steps_on_status_and_updated_at"
      t.index :run_at
    end

    create_table :solid_workflow_events, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid :workflow_id, null: false
      t.uuid :step_id
      t.string :event_type, null: false
      t.jsonb :metadata, default: {}
      t.timestamps

      t.index :workflow_id
      t.index :step_id
      t.index [ :workflow_id, :created_at ], name: "idx_sw_events_on_workflow_and_created_at"
      t.index :event_type
      t.index :created_at
    end

    add_foreign_key :solid_workflow_steps, :solid_workflow_workflows, column: :workflow_id
    add_foreign_key :solid_workflow_events, :solid_workflow_workflows, column: :workflow_id
    add_foreign_key :solid_workflow_events, :solid_workflow_steps, column: :step_id
  end
end
