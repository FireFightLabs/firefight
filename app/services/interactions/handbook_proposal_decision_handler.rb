module Interactions
  # Someone in an incident's channel accepting a handbook edit Halon proposed as written, or dismissing it. A refusal,
  # such as someone having changed the section since, is said to them alone.
  class HandbookProposalDecisionHandler
    extend HandlerAuthorization
    authorize_as Ability::Action::RESOURCE_HANDBOOK, Ability::Action::ACTION_UPDATE

    def self.execute(interaction)
      workspace = interaction.workspace
      adapter = workspace.adapter
      member = WorkspaceMemberProvisioner.find_or_provision!(workspace: workspace, platform_user_id: interaction.user_id, adapter: adapter)
      refusal = HandbookProposalService.new(workspace).decide!(proposal_id: interaction.action_value, member: member,
                                                                accept: interaction.action_id == Identifiers::HANDBOOK_PROPOSAL_ACCEPT)
      adapter.post_ephemeral(channel_id: interaction.channel_id, user_id: interaction.user_id, text: refusal) if refusal
      nil
    end
  end
end
