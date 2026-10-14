module Interactions
  # The answer form's submission. A refusal keeps the form open with the reason.
  class AnswerWorkflowQuestionHandler
    extend HandlerAuthorization
    authorize_as Ability::Action::RESOURCE_WORKFLOWS

    def self.execute(interaction)
      workspace = interaction.workspace
      adapter = workspace.adapter
      member = WorkspaceMemberProvisioner.find_or_provision!(workspace: workspace, platform_user_id: interaction.user_id, adapter: adapter)
      question, blocked = WorkflowQuestionService.for_answer(workspace, interaction.metadata.workflow_question_id, member)
      return nil unless question

      given = adapter.workflow_question_answer(values: interaction.values)
      answered = blocked ? nil : WorkflowQuestionService.answer!(question, by: member, choice: given[:choice], values: given[:values])
      answered&.ok ? nil : adapter.workflow_question_error(blocked || answered.words, question: question)
    end
  end
end
