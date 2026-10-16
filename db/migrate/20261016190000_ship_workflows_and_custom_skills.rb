# Workflows and a workspace's own skills are part of every workspace, so the switches that turned them on per workspace
# are gone. What each runbook runs moves into a workflow it links for the workspaces that never had workflows, as it did
# for those that did (MoveRunbookStepsIntoWorkflows), so nothing runs two ways at once.
class ShipWorkflowsAndCustomSkills < ActiveRecord::Migration[8.1]
  def up
    Runbook.reset_column_information
    Workspace.find_each { |workspace| Runbook.move_runnable_parts!(workspace) }

    execute "DELETE FROM flipper_gates WHERE feature_key IN ('workflows', 'custom_skills')"
    execute "DELETE FROM flipper_features WHERE key IN ('workflows', 'custom_skills')"
  end

  # The runbooks' tool steps, inputs and watch now live only in the linked workflows.
  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
