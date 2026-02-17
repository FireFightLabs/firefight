module Interactions
  class PickUpActionHandler
    def self.execute(interaction)
      workspace = interaction.workspace
      action = IncidentAction.find(interaction.action_value)
      return nil unless action.open? && !action.assigned?

      member = workspace.workspace_memberships.find_by!(platform_user_id: interaction.user_id)

      IncidentActionService.new(workspace).pick_up_action(
        action: action,
        picked_up_by: member
      )

      nil
    rescue ActiveRecord::RecordNotFound
      nil
    end
  end
end
