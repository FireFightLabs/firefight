module Interactions
  # Someone in a chat's thread accepting a skill Halon proposed as written, or dismissing it. A refusal, such as someone
  # having changed the skill since, or the workspace no longer having its own skills, is said to them alone.
  class SkillProposalDecisionHandler
    extend HandlerAuthorization
    authorize_as Ability::Action::RESOURCE_SKILLS, Ability::Action::ACTION_UPDATE

    NOT_ON = "This workspace does not keep skills of its own right now.".freeze

    def self.execute(interaction)
      workspace = interaction.workspace
      adapter = workspace.adapter
      refusal = if Chat::CustomSkill.enabled_for?(workspace)
                  member = WorkspaceMemberProvisioner.find_or_provision!(workspace: workspace, platform_user_id: interaction.user_id, adapter: adapter)
                  SkillProposalService.new(workspace).decide!(proposal_id: interaction.action_value, member: member,
                                                              accept: interaction.action_id == Identifiers::SKILL_PROPOSAL_ACCEPT)
                else
                  NOT_ON
                end
      adapter.post_ephemeral(channel_id: interaction.channel_id, user_id: interaction.user_id, text: refusal) if refusal
      nil
    end
  end
end
