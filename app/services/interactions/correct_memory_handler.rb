module Interactions
  # The correction form's submission. A refusal keeps the form open with the reason.
  class CorrectMemoryHandler
    extend HandlerAuthorization
    authorize_as Ability::Action::RESOURCE_MEMORY, Ability::Action::ACTION_UPDATE

    def self.execute(interaction)
      workspace = interaction.workspace
      adapter = workspace.adapter
      member = WorkspaceMemberProvisioner.find_or_provision!(workspace: workspace, platform_user_id: interaction.user_id, adapter: adapter)

      written = adapter.memory_correction(values: interaction.values)
      refusal = MemoryPostService.new(workspace).correct!(post_id: interaction.metadata.memory_post_id, memory_id: interaction.metadata.memory_id,
                                                          member: member, correction: written[:correction], reason: written[:reason])
      refusal ? adapter.memory_correction_error(refusal) : nil
    end
  end
end
