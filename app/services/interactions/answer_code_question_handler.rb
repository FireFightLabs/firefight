module Interactions
  # The answer form's submission. A refusal keeps the form open with the reason.
  class AnswerCodeQuestionHandler
    extend HandlerAuthorization
    authorize_as Ability::Action::RESOURCE_INVESTIGATIONS, Ability::Action::ACTION_CREATE

    def self.execute(interaction)
      workspace = interaction.workspace
      adapter = workspace.adapter
      member = WorkspaceMemberProvisioner.find_or_provision!(workspace: workspace, platform_user_id: interaction.user_id, adapter: adapter)
      answered = CodeAgentQuestionService.answer_by_id!(workspace, interaction.metadata.code_question_id,
                                                        adapter.code_question_answer(values: interaction.values), by: member)
      answered.ok ? nil : adapter.code_question_error(answered.words)
    end
  end
end
