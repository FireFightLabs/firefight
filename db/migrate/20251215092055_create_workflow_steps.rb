class CreateWorkflowSteps < ActiveRecord::Migration[8.1]
  def change
    create_table :workflow_steps, id: :uuid do |t|
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

      t.index :workflow_id, name: "index_workflow_steps_on_workflow_id"
      t.index [ :workflow_id, :name ], name: "index_workflow_steps_on_workflow_id_and_name"
      t.index [ :workflow_id, :status ], name: "index_workflow_steps_on_workflow_id_and_status"
      t.index :status
      t.index :run_at
    end

    add_foreign_key :workflow_steps, :workflows
  end
end
