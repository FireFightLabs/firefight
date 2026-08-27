class MakeSolidWorkflowStepNamesUnique < ActiveRecord::Migration[8.1]
  def change
    remove_index :solid_workflow_steps, name: "index_solid_workflow_steps_on_workflow_id_and_name"
    add_index :solid_workflow_steps, [ :workflow_id, :name ],
      unique: true,
      name: "index_solid_workflow_steps_on_workflow_id_and_name"
  end
end
