# Someone in an incident channel confirming a memory Halon learned or disputed, or marking it not right.
module Interactions
  class MemoryDecisionHandler
    extend HandlerAuthorization
    authorize_as Ability::Action::RESOURCE_MEMORY, Ability::Action::ACTION_UPDATE

    def self.execute(interaction)
      reference, memory_id = interaction.action_value.to_s.split(":", 2)
      workspace = interaction.workspace
      member = WorkspaceMemberProvisioner.find_or_provision!(workspace: workspace, platform_user_id: interaction.user_id, adapter: workspace.adapter)

      MemoryPostService.new(workspace).decide!(reference: reference, memory_id: memory_id, member: member,
                                               confirmed: interaction.action_id == Identifiers::MEMORY_CONFIRM,
                                               channel_id: interaction.channel_id, message_id: interaction.message_id)
      nil
    end
  end
end
