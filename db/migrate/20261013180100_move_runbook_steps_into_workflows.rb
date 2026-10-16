# Only workspaces that already had workflows moved here. Every other moved once workflows shipped to every workspace
# (ShipWorkflowsAndCustomSkills). The flag's actors are read straight from Flipper's table, since its constant is gone.
class MoveRunbookStepsIntoWorkflows < ActiveRecord::Migration[8.1]
  def up
    Runbook.reset_column_information
    ids = select_values("SELECT value FROM flipper_gates WHERE feature_key = 'workflows' AND key = 'actors'")
    Workspace.where(id: ids.filter_map { |actor| actor.delete_prefix("Workspace;") if actor.start_with?("Workspace;") }).find_each do |workspace|
      Runbook.move_runnable_parts!(workspace)
    end
  end

  # The runbooks' tool steps, inputs and watch now live only in the linked workflows, so rolling back past here would
  # drop the link to them.
  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
