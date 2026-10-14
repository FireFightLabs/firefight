module Interactions
  # Answer on a workflow's question opens its form. Only the people it asked can answer, and anyone else is told who
  # can. trigger_id expires in three seconds, so this stays sync.
  class OpenWorkflowQuestionHandler
    extend HandlerAuthorization
    authorize_as Ability::Action::RESOURCE_WORKFLOWS

    def self.execute(interaction)
      workspace = interaction.workspace
      adapter = workspace.adapter
      member = WorkspaceMemberProvisioner.find_or_provision!(workspace: workspace, platform_user_id: interaction.user_id, adapter: adapter)
      question, blocked = WorkflowQuestionService.for_answer(workspace, interaction.action_value, member)
      if blocked
        adapter.post_ephemeral(channel_id: interaction.channel_id, user_id: interaction.user_id, text: blocked)
        return nil
      end

      adapter.open_workflow_question_modal(trigger_id: interaction.trigger_id, question: question)
      nil
    rescue AdapterError::TriggerExpired
      nil
    end
  end
end
