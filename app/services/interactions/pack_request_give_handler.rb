module Interactions
  # Give pack on a member's request, in an admin's direct messages. The gateway checks that whoever pressed it may grant,
  # and the grant is the same one the Permissions screen makes.
  class PackRequestGiveHandler
    extend HandlerAuthorization
    authorize_as Ability::Action::RESOURCE_PERMISSIONS, Ability::Action::ACTION_CREATE

    def self.execute(interaction)
      workspace = interaction.workspace
      request = Ability::PackRequest.where(workspace: workspace).find(interaction.action_value)
      member = workspace.workspace_memberships.find_by!(platform_user_id: interaction.user_id)

      result = PackRequestService.give!(request, by: member)
      workspace.adapter.post_ephemeral(channel_id: interaction.channel_id, user_id: interaction.user_id, text: result.words) unless result.ok
      nil
    rescue ActiveRecord::RecordNotFound
      nil
    end
  end
end
