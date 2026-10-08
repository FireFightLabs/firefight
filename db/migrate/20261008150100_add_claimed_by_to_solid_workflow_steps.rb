# The job running a step, so the same job handed back by a stopped worker takes the step up again at once rather than
# waiting for the sweeper to call it orphaned.
class AddClaimedByToSolidWorkflowSteps < ActiveRecord::Migration[8.1]
  def change
    add_column :solid_workflow_steps, :claimed_by, :string
  end
end
