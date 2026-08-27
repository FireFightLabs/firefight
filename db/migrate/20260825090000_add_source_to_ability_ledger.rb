class AddSourceToAbilityLedger < ActiveRecord::Migration[8.1]
  NEW_RESOURCES = %w[incident_roles webhooks integrations api_keys permissions workspace].freeze

  def up
    add_column :ability_invocations, :source, :string
    add_column :ability_approvals, :source, :string
    Ability::Action.sync_system_actions!
  end

  def down
    keys = NEW_RESOURCES.product(Ability::Action::ACTIONS).map { |resource, action| "#{resource}.#{action}" }
    Ability::Action.where(workspace_id: nil, key: keys).destroy_all
    remove_column :ability_approvals, :source
    remove_column :ability_invocations, :source
  end
end
