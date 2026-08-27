class AddCheckpointToSolidWorkflowSteps < ActiveRecord::Migration[8.1]
  def change
    add_column :solid_workflow_steps, :checkpoint, :jsonb
  end
end
