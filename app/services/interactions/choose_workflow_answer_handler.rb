module Interactions
  # One of a workflow question's choices picked in its direct message, which answers it in one click. Only the people it
  # asked can, and anyone else is told who can.
  class ChooseWorkflowAnswerHandler
    extend HandlerAuthorization
    authorize_as Ability::Action::RESOURCE_WORKFLOWS

    def self.execute(interaction)
      workspace = interaction.workspace
      adapter = workspace.adapter
      member = WorkspaceMemberProvisioner.find_or_provision!(workspace: workspace, platform_user_id: interaction.user_id, adapter: adapter)
      id, index = interaction.action_value.to_s.split(":", 2)
      answered = WorkflowQuestionService.choose_by_id!(workspace, id, Integer(index.to_s, exception: false), by: member)
      adapter.post_ephemeral(channel_id: interaction.channel_id, user_id: interaction.user_id, text: answered.words) unless answered.ok
      nil
    end
  end
end
