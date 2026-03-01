class MigrateToSolidWorkflowEngine < ActiveRecord::Migration[8.1]
  def change
    rename_table :workflows, :solid_workflow_workflows
    rename_table :workflow_steps, :solid_workflow_steps
    rename_table :workflow_events, :solid_workflow_events
    rename_column :solid_workflow_events, :workflow_step_id, :step_id
  end
end
