# Only workspaces that already have workflows move now. Any other keeps its runbooks exactly as they are until the flag
# is turned on for it (FeatureFlags.enable!).
class MoveRunbookStepsIntoWorkflows < ActiveRecord::Migration[8.1]
  def up
    Runbook.reset_column_information
    FeatureFlags.workspaces_with(FeatureFlags::WORKFLOWS).find_each do |workspace|
      Runbook.move_runnable_parts!(workspace)
    end
  end

  # The runbooks' tool steps, inputs and watch now live only in the linked workflows, so rolling back past here would
  # drop the link to them.
  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
