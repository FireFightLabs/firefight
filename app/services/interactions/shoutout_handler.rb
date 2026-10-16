module Interactions
  class ShoutoutHandler
    extend HandlerAuthorization
    authorize_as Ability::Action::RESOURCE_INCIDENTS, Ability::Action::ACTION_UPDATE

    def self.execute(interaction)
      workspace = interaction.workspace
      incident = workspace.incidents.find(interaction.metadata.incident_id)

      recipient_user_id = interaction.values.dig(Identifiers::SHOUTOUT_RECIPIENT_BLOCK, Identifiers::SHOUTOUT_RECIPIENT_SELECT, "selected_user")
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
        message: interaction.values.dig(Identifiers::SHOUTOUT_MESSAGE_BLOCK, Identifiers::SHOUTOUT_MESSAGE_INPUT, "value")
      )

      nil
    rescue ActiveRecord::RecordNotFound, JSON::ParserError
      nil
    end
  end
end
