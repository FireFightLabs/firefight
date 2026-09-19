class AddChatsAbilityActions < ActiveRecord::Migration[8.1]
  # A missing Ability::Action denies everyone, admins included, so the rows exist before the chat page asks for them.
  def up
    Ability::Action.sync_system_actions!
  end

  def down
    keys = Ability::Action::ACTIONS.map { |action| "#{Ability::Action::RESOURCE_CHATS}.#{action}" }
    Ability::Action.where(workspace_id: nil, key: keys).destroy_all
  end
end
