module Interactions
  # Run now or Cancel on a workflow Halon made in a chat, from its message in the thread. Whoever may press them on the
  # dashboard may here, and a press someone may not make is answered privately with why. The message redraws itself
  # once the workflow moves.
  class ChatWorkflowHandler
    extend HandlerAuthorization
    authorize_as Ability::Action::RESOURCE_WORKFLOWS, Ability::Action::ACTION_CREATE

    def self.execute(interaction)
      workspace = interaction.workspace
      workflow = workspace.workflows.find(interaction.action_value)
      member = WorkspaceMemberProvisioner.find_or_provision!(workspace: workspace, platform_user_id: interaction.user_id, adapter: workspace.adapter)
      action = interaction.action_id == Identifiers::CHAT_WORKFLOW_RUN_NOW ? Workflow::ACTION_RUN_NOW : workflow.stop_action

      result = Conversation::Workflows.press!(workflow, action, by: member)
      workspace.adapter.post_ephemeral(channel_id: interaction.channel_id, user_id: interaction.user_id, text: result.words) unless result.ok
      nil
    rescue ActiveRecord::RecordNotFound
      nil
    end
  end
end
