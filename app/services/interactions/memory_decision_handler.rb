# Someone in the incident channel confirming a lesson Halon learned from it, or marking it not right.
module Interactions
  class MemoryDecisionHandler
    extend HandlerAuthorization
    authorize_as Ability::Action::RESOURCE_INCIDENTS, Ability::Action::ACTION_UPDATE

    def self.execute(interaction)
      incident_id, memory_id = interaction.action_value.to_s.split(":", 2)
      workspace = interaction.workspace
      incident = workspace.incidents.find_by(id: incident_id)
      memory = Chat::Memory.where(workspace: workspace, source: incident).find_by(id: memory_id) if incident
      return unless memory

      member = WorkspaceMemberProvisioner.find_or_provision!(workspace: workspace, platform_user_id: interaction.user_id, adapter: workspace.adapter)
      return unless member

      if interaction.action_id == Identifiers::MEMORY_CONFIRM
        memory.confirm!(by: member)
      else
        memory.reject!(by: member, reason: "Marked not right in #{incident.identifier}")
      end
      IncidentLearningService.new(workspace).redraw(incident, channel_id: interaction.channel_id, message_id: interaction.message_id)
      nil
    end
  end
end
