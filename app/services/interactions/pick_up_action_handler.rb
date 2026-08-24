module Interactions
  class PickUpActionHandler
    extend HandlerAuthorization
    authorize_as Ability::Action::RESOURCE_INCIDENTS, Ability::Action::ACTION_UPDATE

    def self.execute(interaction)
      workspace = interaction.workspace
      action = IncidentAction.in_workspace(workspace).find(interaction.action_value)
      return nil unless action.open? && !action.assigned?

      member = workspace.workspace_memberships.find_by!(platform_user_id: interaction.user_id)

      IncidentActionService.new(workspace).pick_up_action(
        action: action,
        picked_up_by: member
      )

      OpenModalRefresh.call(interaction, workspace)
      nil
    rescue ActiveRecord::RecordNotFound
      nil
    end
  end
end
