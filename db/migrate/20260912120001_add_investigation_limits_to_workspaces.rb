# Defaults live in code. A row here is an operator override for one workspace.
class AddInvestigationLimitsToWorkspaces < ActiveRecord::Migration[8.1]
  def up
    add_column :workspaces, :investigation_max_turns, :integer
    add_column :workspaces, :investigation_max_tokens, :integer
    add_column :workspaces, :investigation_confidence_threshold, :decimal, precision: 3, scale: 2
    Ability::Action.sync_system_actions!
  end

  def down
    remove_column :workspaces, :investigation_max_turns
    remove_column :workspaces, :investigation_max_tokens
    remove_column :workspaces, :investigation_confidence_threshold
  end
end
