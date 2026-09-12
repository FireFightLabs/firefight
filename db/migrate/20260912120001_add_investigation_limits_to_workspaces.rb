# Defaults live in code. These columns are an operator's override for one workspace.
class AddInvestigationLimitsToWorkspaces < ActiveRecord::Migration[8.1]
  def up
    add_column :workspaces, :investigation_max_turns, :integer
    add_column :workspaces, :investigation_max_spend_cents, :integer
    Ability::Action.sync_system_actions!
  end

  def down
    remove_column :workspaces, :investigation_max_turns
    remove_column :workspaces, :investigation_max_spend_cents
  end
end
