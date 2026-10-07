module Interactions
  # Ask an admin on a change Halon was refused in a chat's thread. Only the person refused can ask, and the admins hear
  # at most once a day. What happened is said to whoever pressed it.
  class PackRequestAskHandler
    extend HandlerAuthorization
    authorize_as Ability::Action::RESOURCE_CHATS, Ability::Action::ACTION_UPDATE

    def self.execute(interaction)
      workspace = interaction.workspace
      request = Ability::PackRequest.where(workspace: workspace).find(interaction.action_value)
      member = workspace.workspace_memberships.find_by!(platform_user_id: interaction.user_id)

      result = PackRequestService.ask!(request, by: member)
      workspace.adapter.post_ephemeral(channel_id: interaction.channel_id, user_id: interaction.user_id, text: result.words)
      nil
    rescue ActiveRecord::RecordNotFound
      nil
    end
  end
end
