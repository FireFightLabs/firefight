class CreateWorkflowEventsTable < ActiveRecord::Migration[8.1]
  def change
    create_table :workflow_events, id: :uuid do |t|
      t.uuid :workflow_id, null: false
      t.uuid :workflow_step_id
      t.string :event_type, null: false
      t.jsonb :metadata, default: {}
      t.timestamps

      t.index :workflow_id, name: "index_workflow_events_on_workflow_id"
      t.index :workflow_step_id, name: "index_workflow_events_on_workflow_step_id"
      t.index [ :workflow_id, :created_at ], name: "index_workflow_events_on_workflow_and_created_at"
      t.index :event_type
      t.index :created_at
    end

    add_foreign_key :workflow_events, :workflows
    add_foreign_key :workflow_events, :workflow_steps
  end
end
