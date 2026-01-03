class AddWorkflowStepsStatusUpdatedAtIndex < ActiveRecord::Migration[8.1]
  def change
    add_index :workflow_steps, [ :status, :updated_at ],
              name: "index_workflow_steps_on_status_and_updated_at"
  end
end
