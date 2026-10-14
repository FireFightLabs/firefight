# How long a step used the run's sandbox and what that time cost at its box's price, so the run's page shows it beside
# the step's AI.
class AddSandboxTimeToWorkflowRunSteps < ActiveRecord::Migration[8.1]
  def change
    add_column :workflow_run_steps, :sandbox_seconds, :integer, null: false, default: 0
    add_column :workflow_run_steps, :sandbox_micros, :bigint, null: false, default: 0
  end
end
