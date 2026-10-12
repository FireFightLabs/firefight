class AddChannelPostAbilityAction < ActiveRecord::Migration[8.1]
  # Listed in the grant picker and offered to Halon from this row, so it exists before anyone looks for it.
  def up
    Ability::Action.sync_system_actions!
  end

  def down
    Ability::Action.where(workspace_id: nil, key: Ability::Action::CHANNEL_POST).destroy_all
  end
end
