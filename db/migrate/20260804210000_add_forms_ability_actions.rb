class AddFormsAbilityActions < ActiveRecord::Migration[8.1]
  class MigrationApiKey < ActiveRecord::Base
    self.table_name = "api_keys"
  end

  # Ability::Action.lookup returning nil denies everyone, admins included, so
  # the rows for a new resource have to exist before the tools that name it.
  def up
    Ability::Action.sync_system_actions!

    read_action = Ability::Action.find_by(workspace_id: nil, key: "#{ApiKey::RESOURCE_FORMS}.#{ApiKey::ACTION_READ}")
    return unless read_action

    # Reading a form's configuration used to sit under custom_fields, so a key
    # granted that keeps it rather than silently losing get_form.
    MigrationApiKey.where(workspace_membership_id: nil).where.not(permissions: {}).find_each do |key|
      next unless key.permissions[ApiKey::RESOURCE_CUSTOM_FIELDS]&.include?(ApiKey::ACTION_READ)

      key.update_columns(permissions: key.permissions.merge(ApiKey::RESOURCE_FORMS => [ ApiKey::ACTION_READ ]))
      Ability::Grant.find_or_create_by!(
        workspace_id: key.workspace_id,
        principal_type: "ApiKey",
        principal_id: key.id,
        action_id: read_action.id
      )
    end
  end

  def down
    Ability::Action.where(workspace_id: nil, key: [ "#{ApiKey::RESOURCE_FORMS}.read", "#{ApiKey::RESOURCE_FORMS}.create",
                                                    "#{ApiKey::RESOURCE_FORMS}.update", "#{ApiKey::RESOURCE_FORMS}.delete" ]).destroy_all
  end
end
