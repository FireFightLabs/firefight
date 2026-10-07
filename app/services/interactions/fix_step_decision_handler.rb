module Interactions
  # Run, Dismiss or Ask again on a step of a fix that was approved. The step runs as whoever applied the fix, since that
  # is who it was approved for, and the thread's message redraws.
  class FixStepDecisionHandler
    extend HandlerAuthorization
    authorize_as Ability::Action::RESOURCE_INVESTIGATIONS, Ability::Action::ACTION_CREATE

    def self.execute(interaction)
      workspace = interaction.workspace
      step = Investigation::RemediationStep.in_workspace(workspace).find(interaction.action_value)
      member = workspace.workspace_memberships.find_by!(platform_user_id: interaction.user_id)

      refusal = case interaction.action_id
      when Identifiers::FIX_STEP_RUN then Investigation::FixRunner.run_approved!(step, by: member)
      when Identifiers::FIX_STEP_DISMISS then Investigation::FixRunner.dismiss_approved!(step, by: member)
      else Investigation::FixRunner.ask_again!(step, by: member)
      end
      workspace.adapter.post_ephemeral(channel_id: interaction.channel_id, user_id: interaction.user_id, text: refusal) if refusal
      nil
    rescue ActiveRecord::RecordNotFound
      nil
    end
  end
end
