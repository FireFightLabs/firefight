module Interactions
  # The edit form's submission, which accepts the proposal with the person's wording. A refusal keeps the form open with
  # the reason.
  class EditHandbookProposalHandler
    extend HandlerAuthorization
    authorize_as Ability::Action::RESOURCE_HANDBOOK, Ability::Action::ACTION_UPDATE

    def self.execute(interaction)
      workspace = interaction.workspace
      adapter = workspace.adapter
      member = WorkspaceMemberProvisioner.find_or_provision!(workspace: workspace, platform_user_id: interaction.user_id, adapter: adapter)
      refusal = HandbookProposalService.new(workspace).edit!(proposal_id: interaction.metadata.handbook_proposal_id, member: member,
                                                              text: adapter.handbook_proposal_text(values: interaction.values))
      refusal ? adapter.handbook_proposal_error(refusal) : nil
    end
  end
end
