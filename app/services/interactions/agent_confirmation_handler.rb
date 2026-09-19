# The call runs as whoever pressed the button, not whoever asked.
module Interactions
  class AgentConfirmationHandler
    extend HandlerAuthorization
    authorize_as Ability::Action::RESOURCE_INVESTIGATIONS, Ability::Action::ACTION_CREATE

    def self.execute(interaction)
      conversation_id, tool_call_id = interaction.action_value.to_s.split(":", 2)
      workspace = interaction.workspace
      conversation = workspace.conversations.find_by(id: conversation_id)
      return unless conversation

      member = WorkspaceMemberProvisioner.find_or_provision!(
        workspace: workspace, platform_user_id: interaction.user_id, adapter: workspace.adapter
      )
      return unless member

      approved = interaction.action_id == Identifiers::AGENT_CONFIRM
      Conversation::Confirming.decide(conversation, [ { tool_call_id: tool_call_id, approved: approved } ], by: member)
      Conversation::Confirming.redraw(
        conversation, tool_call_id,
        channel_id: interaction.channel_id, message_id: interaction.message_id
      )
      nil
    end
  end
end
