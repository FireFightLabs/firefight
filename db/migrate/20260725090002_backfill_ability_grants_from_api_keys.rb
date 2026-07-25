class BackfillAbilityGrantsFromApiKeys < ActiveRecord::Migration[8.1]
  class MigrationApiKey < ActiveRecord::Base
    self.table_name = "api_keys"
  end

  def up
    Ability::Action.sync_system_actions!

    MigrationApiKey.where(workspace_membership_id: nil).where.not(permissions: {}).find_each do |key|
      key.permissions.each do |resource, actions|
        next unless actions.is_a?(Array)

        actions.each do |action|
          ability_action = Ability::Action.find_by(workspace_id: nil, key: "#{resource}.#{action}")
          next unless ability_action

          Ability::Grant.find_or_create_by!(
            workspace_id: key.workspace_id,
            principal_type: "ApiKey",
            principal_id: key.id,
            action_id: ability_action.id
          )
        end
      end
    end
  end

  def down
    Ability::Grant.where(principal_type: "ApiKey").delete_all
  end
end
