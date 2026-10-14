module Interactions
  # Done on a Manual step's task that collects no note, which marks it done in one click. Only whoever it was given to
  # can, or anyone for a task given to anyone, and anyone else is told who can.
  class FinishWorkflowTaskHandler
    extend HandlerAuthorization
    authorize_as Ability::Action::RESOURCE_WORKFLOWS

    def self.execute(interaction)
      workspace = interaction.workspace
      adapter = workspace.adapter
      member = WorkspaceMemberProvisioner.find_or_provision!(workspace: workspace, platform_user_id: interaction.user_id, adapter: adapter)
      done = WorkflowQuestionService.finish_by_id!(workspace, interaction.action_value, by: member)
      adapter.post_ephemeral(channel_id: interaction.channel_id, user_id: interaction.user_id, text: done.words) unless done.ok
      nil
    end
  end
end
