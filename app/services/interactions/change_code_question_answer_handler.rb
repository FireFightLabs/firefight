module Interactions
  # The change form's submission. A refusal keeps the form open with the reason.
  class ChangeCodeQuestionAnswerHandler
    extend HandlerAuthorization
    authorize_as Ability::Action::RESOURCE_INVESTIGATIONS, Ability::Action::ACTION_CREATE

    def self.execute(interaction)
      workspace = interaction.workspace
      adapter = workspace.adapter
      member = WorkspaceMemberProvisioner.find_or_provision!(workspace: workspace, platform_user_id: interaction.user_id, adapter: adapter)
      given = adapter.code_question_change(values: interaction.values)
      changed = CodeAgentQuestionService.change_by_id!(workspace, interaction.metadata.code_question_id, given.answer, by: member, option: given.option)
      changed.ok ? nil : adapter.code_question_change_error(changed.words)
    end
  end
end
