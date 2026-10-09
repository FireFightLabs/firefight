module Interactions
  # One of a coding agent's options picked from its question in the thread, which answers it in one click. Only the person
  # the change runs as can, and anyone else is told who can.
  class ChooseCodeQuestionOptionHandler
    extend HandlerAuthorization
    authorize_as Ability::Action::RESOURCE_INVESTIGATIONS, Ability::Action::ACTION_CREATE

    def self.execute(interaction)
      workspace = interaction.workspace
      adapter = workspace.adapter
      member = WorkspaceMemberProvisioner.find_or_provision!(workspace: workspace, platform_user_id: interaction.user_id, adapter: adapter)
      id, index = interaction.action_value.to_s.split(":", 2)
      answered = CodeAgentQuestionService.answer_by_id!(workspace, id, nil, by: member, option: Integer(index.to_s, exception: false) || -1)
      adapter.post_ephemeral(channel_id: interaction.channel_id, user_id: interaction.user_id, text: answered.words) unless answered.ok
      nil
    end
  end
end
