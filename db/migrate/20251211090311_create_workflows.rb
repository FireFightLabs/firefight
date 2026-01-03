class CreateWorkflows < ActiveRecord::Migration[8.1]
  def change
    create_table :workflows, id: :uuid do |t|
      t.string :name, null: false
      t.string :workflow_class, null: false
      t.string :subject_type, null: false
      t.uuid :subject_id, null: false
      t.string :state, null: false, default: "pending"
      t.jsonb :context, null: false, default: {}
      t.jsonb :workflow_config, default: {}
      t.datetime :started_at
      t.datetime :completed_at
      t.string :cancelled_by
      t.text :cancellation_reason
      t.timestamps

      t.index [ :subject_type, :subject_id ], name: "index_workflows_on_subject"
      t.index :state
      t.index :workflow_class
      t.index :created_at
      t.index [ :state, :updated_at ], name: "index_workflows_on_state_and_updated_at"
    end
  end
end
