module Interactions
  # The rename form's submission. A refusal keeps the form open with the reason.
  class RenameActionItemHandler
    extend HandlerAuthorization
    authorize_as Ability::Action::RESOURCE_INCIDENTS, Ability::Action::ACTION_UPDATE

    def self.execute(interaction)
      workspace = interaction.workspace
      adapter = workspace.adapter
      action = IncidentAction.in_workspace(workspace).active.find(interaction.metadata.action_item_id)
      member = workspace.workspace_memberships.find_by!(platform_user_id: interaction.user_id)

      refusal = IncidentActionService.new(workspace).rename_action(
        action: action, description: adapter.renamed_action_title(values: interaction.values), renamed_by: member
      )
      refusal ? adapter.rename_action_error(refusal) : nil
    rescue ActiveRecord::RecordNotFound
      adapter.rename_action_error("That item is gone. Close this and look again.")
    end
  end
end
