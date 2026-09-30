class AddMemoryAbilityActions < ActiveRecord::Migration[8.1]
  # Listed in the grant picker from these rows, so they exist before anyone looks for them.
  def up
    Ability::Action.sync_system_actions!
  end

  def down
    keys = Ability::Action::ACTIONS.map { |action| "#{Ability::Action::RESOURCE_MEMORY}.#{action}" }
    Ability::Action.where(workspace_id: nil, key: keys).destroy_all
  end
end
