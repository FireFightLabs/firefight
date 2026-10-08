module Interactions
  # Continue or Stop on a code change paused at its spending limit. It runs as whoever asked for the change, so only they
  # decide, and anyone else is told who can.
  class CodePauseDecisionHandler
    extend HandlerAuthorization
    authorize_as Ability::Action::RESOURCE_INVESTIGATIONS, Ability::Action::ACTION_CREATE

    def self.execute(interaction)
      workspace = interaction.workspace
      pause = CodeAgentSession::Pause.find_by(id: interaction.action_value, workspace_id: workspace.id)
      return nil unless pause

      member = WorkspaceMemberProvisioner.find_or_provision!(workspace: workspace, platform_user_id: interaction.user_id, adapter: workspace.adapter)
      refusal = if interaction.action_id == Identifiers::CODE_PAUSE_CONTINUE
        CodeAgentPauseService.continue!(pause, by: member)
      else
        CodeAgentPauseService.stop!(pause, by: member)
      end
      workspace.adapter.post_ephemeral(channel_id: interaction.channel_id, user_id: interaction.user_id, text: refusal) if refusal
      nil
    end
  end
end
