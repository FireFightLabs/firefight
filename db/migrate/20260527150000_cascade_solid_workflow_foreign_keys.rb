class CascadeSolidWorkflowForeignKeys < ActiveRecord::Migration[8.1]
  def change
    reversible do |dir|
      dir.up do
        remove_foreign_key :solid_workflow_steps,  :solid_workflow_workflows, column: :workflow_id
        remove_foreign_key :solid_workflow_events, :solid_workflow_workflows, column: :workflow_id
        remove_foreign_key :solid_workflow_events, :solid_workflow_steps,     column: :step_id

        add_foreign_key :solid_workflow_steps,  :solid_workflow_workflows, column: :workflow_id, on_delete: :cascade
        add_foreign_key :solid_workflow_events, :solid_workflow_workflows, column: :workflow_id, on_delete: :cascade
        add_foreign_key :solid_workflow_events, :solid_workflow_steps,     column: :step_id,     on_delete: :cascade
      end

      dir.down do
        remove_foreign_key :solid_workflow_steps,  :solid_workflow_workflows, column: :workflow_id
        remove_foreign_key :solid_workflow_events, :solid_workflow_workflows, column: :workflow_id
        remove_foreign_key :solid_workflow_events, :solid_workflow_steps,     column: :step_id

        add_foreign_key :solid_workflow_steps,  :solid_workflow_workflows, column: :workflow_id
        add_foreign_key :solid_workflow_events, :solid_workflow_workflows, column: :workflow_id
        add_foreign_key :solid_workflow_events, :solid_workflow_steps,     column: :step_id
      end
    end
  end
end
