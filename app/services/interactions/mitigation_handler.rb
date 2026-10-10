module Interactions
  # Keep it, One more hour or Undo now on a temporary change Halon made, from its reminder or any line it said. Whoever may
  # change it on the dashboard may press them, and anyone else is told who can.
  class MitigationHandler
    extend HandlerAuthorization
    authorize_as Ability::Action::RESOURCE_INVESTIGATIONS, Ability::Action::ACTION_CREATE

    ACTIONS = {
      Identifiers::MITIGATION_KEEP => :keep!, Identifiers::MITIGATION_EXTEND => :extend!, Identifiers::MITIGATION_UNDO => :undo_now!
    }.freeze

    def self.execute(interaction)
      workspace = interaction.workspace
      mitigation = Chat::Mitigation.where(workspace_id: workspace.id).find_by(id: interaction.action_value)
      return nil unless mitigation

      member = WorkspaceMemberProvisioner.find_or_provision!(workspace: workspace, platform_user_id: interaction.user_id, adapter: workspace.adapter)
      refusal = Conversation::Mitigations.pressed!(mitigation, ACTIONS.fetch(interaction.action_id), by: member,
                                                                                                    channel_id: interaction.channel_id, message_id: interaction.message_id)
      workspace.adapter.post_ephemeral(channel_id: interaction.channel_id, user_id: interaction.user_id, text: refusal) if refusal
      nil
    end
  end
end
