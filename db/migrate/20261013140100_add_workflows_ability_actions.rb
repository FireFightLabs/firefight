class AddWorkflowsAbilityActions < ActiveRecord::Migration[8.1]
  # Building, running and publishing workflows is authorized from these rows, so they exist before anyone asks.
  def up
    Ability::Action.sync_system_actions!
  end

  def down
    Ability::Action.where(workspace_id: nil, key: Ability::Action.keys_for([ "workflows" ])).destroy_all
  end
end
