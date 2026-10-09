module Interactions
  # Cancel on a fix's progress while it is being applied, after the platform's own confirm. Who may start a run may stop its
  # fix, and only the clicker is told what happened. The progress message redraws itself.
  class CancelFixHandler
    extend HandlerAuthorization
    authorize_as Ability::Action::RESOURCE_INVESTIGATIONS, Ability::Action::ACTION_CREATE

    def self.execute(interaction)
      workspace = interaction.workspace
      plan = Investigation::RemediationPlan.in_workspace(workspace).find(interaction.action_value)
      member = workspace.workspace_memberships.find_by!(platform_user_id: interaction.user_id)

      said = Investigation::FixRunner.cancel!(plan, by: member) || Investigation::FixRunner.cancelled_message(plan)
      workspace.adapter.post_ephemeral(channel_id: interaction.channel_id, user_id: interaction.user_id, text: said)
      nil
    rescue ActiveRecord::RecordNotFound
      nil
    end
  end
end
