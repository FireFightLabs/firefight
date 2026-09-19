class AddChatsAbilityActions < ActiveRecord::Migration[8.1]
  # A missing action denies everyone, admins included.
  def up
    Ability::Action.sync_system_actions!
  end

  def down
    keys = Ability::Action::ACTIONS.map { |action| "#{Ability::Action::RESOURCE_CHATS}.#{action}" }
    Ability::Action.where(workspace_id: nil, key: keys).destroy_all
  end
end
