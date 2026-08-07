module Interactions
  class MarkActionDoneHandler
    def self.execute(interaction)
      workspace = interaction.workspace
      action = IncidentAction.in_workspace(workspace).find(interaction.action_value)
      return nil if action.done?

      member = workspace.workspace_memberships.find_by!(platform_user_id: interaction.user_id)

      IncidentActionService.new(workspace).complete_action(
        action: action,
        completed_by: member
      )

      nil
    rescue ActiveRecord::RecordNotFound
      nil
    end
  end
end
