class AddDefinitionsToSolidWorkflow < ActiveRecord::Migration[8.1]
  def change
    change_table :solid_workflow_workflows, bulk: true do |t|
      t.jsonb :definition
      t.string :start_key
      t.uuid :parent_step_id
      t.jsonb :result
      t.index :start_key, unique: true, where: "start_key IS NOT NULL", name: "index_solid_workflow_workflows_on_start_key"
      t.index :parent_step_id, where: "parent_step_id IS NOT NULL", name: "index_solid_workflow_workflows_on_parent_step_id"
    end

    change_table :solid_workflow_steps, bulk: true do |t|
      t.string :kind
      t.string :label
      t.jsonb :config
      t.jsonb :incoming, null: false, default: []
      t.string :route
      t.string :on_failure
      t.integer :timeout_seconds
      t.datetime :timeout_at
      t.datetime :first_started_at
      t.string :signal_key
      t.jsonb :signal_payload
      t.integer :wake_requests, null: false, default: 0
      t.index :signal_key, where: "signal_key IS NOT NULL", name: "index_solid_workflow_steps_on_signal_key"
      t.index :timeout_at, where: "timeout_at IS NOT NULL", name: "index_solid_workflow_steps_on_timeout_at"
    end
  end
end
