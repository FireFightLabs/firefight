module Interactions
  class ShoutoutHandler
    extend HandlerAuthorization
    authorize_as Ability::Action::RESOURCE_INCIDENTS, Ability::Action::ACTION_UPDATE

    def self.execute(interaction)
      workspace = interaction.workspace
      incident = workspace.incidents.find(interaction.metadata.incident_id)

      recipient_user_id = workspace.adapter.submitted_value(values: interaction.values, block_id: Identifiers::SHOUTOUT_RECIPIENT_BLOCK, input_id: Identifiers::SHOUTOUT_RECIPIENT_SELECT, kind: PlatformAdapter::Input::USER)
      to_member = if recipient_user_id
        WorkspaceMemberProvisioner.find_or_provision!(
          workspace: workspace,
          platform_user_id: recipient_user_id,
          adapter: workspace.adapter
        )
      end

      ShoutoutService.new(workspace).give(
        incident: incident,
        from: workspace.workspace_memberships.find_by!(platform_user_id: interaction.user_id),
        to: to_member,
        message: workspace.adapter.submitted_value(values: interaction.values, block_id: Identifiers::SHOUTOUT_MESSAGE_BLOCK, input_id: Identifiers::SHOUTOUT_MESSAGE_INPUT, kind: PlatformAdapter::Input::TEXT)
      )

      nil
    rescue ActiveRecord::RecordNotFound, JSON::ParserError
      nil
    end
  end
end
