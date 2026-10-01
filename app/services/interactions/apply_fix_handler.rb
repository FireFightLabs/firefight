module Interactions
  # Apply fix on an answer, after Slack's own confirm. The steps run as whoever clicked, so who may start a run may
  # apply its fix, and each step is still the gateway's to allow. A refusal is told only to them.
  class ApplyFixHandler
    extend HandlerAuthorization
    authorize_as Ability::Action::RESOURCE_INVESTIGATIONS, Ability::Action::ACTION_CREATE

    def self.execute(interaction)
      workspace = interaction.workspace
      plan = Investigation::RemediationPlan.in_workspace(workspace).find(interaction.action_value)
      member = workspace.workspace_memberships.find_by!(platform_user_id: interaction.user_id)

      refusal = Investigation::FixRunner.apply!(plan, by: member, from: AbilityGateway::SOURCE_SLACK)
      workspace.adapter.post_ephemeral(channel_id: interaction.channel_id, user_id: interaction.user_id, text: refusal) if refusal
      nil
    rescue ActiveRecord::RecordNotFound
      nil
    end
  end
end
