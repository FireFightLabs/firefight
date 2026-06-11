class AddPauseColumnsToSolidWorkflowWorkflows < ActiveRecord::Migration[8.1]
  def change
    change_table :solid_workflow_workflows, bulk: true do |t|
      t.datetime :paused_at
      t.string :paused_by
      t.text :pause_reason
      t.datetime :resumed_at
      t.string :resumed_by
    end
  end
end
