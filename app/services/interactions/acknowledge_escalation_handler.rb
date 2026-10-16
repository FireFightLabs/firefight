module Interactions
  class AcknowledgeEscalationHandler
    extend HandlerAuthorization
    authorize_as Ability::Action::RESOURCE_INCIDENTS, Ability::Action::ACTION_UPDATE

    def self.execute(interaction)
      workspace = interaction.workspace
      payload = JSON.parse(interaction.action_value || "{}")
      incident = workspace.incidents.find(payload["incident_id"])
      escalation_event = incident.incident_events.find(payload["escalation_event_id"])

      return nil unless escalation_event.metadata["escalated_to_platform_user_id"] == interaction.user_id

      acknowledged_by = workspace.workspace_memberships.find_by(platform_user_id: interaction.user_id)
      acknowledged = IncidentLifecycleService.new(workspace).acknowledge_escalation(
        incident, escalation_event, platform_user_id: interaction.user_id, acknowledged_by: acknowledged_by
      )
      return nil unless acknowledged

      pressed = workspace.adapter.pressed_message(raw: interaction.raw)
      channel_id = pressed[:channel_id] || interaction.channel_id

      if channel_id && pressed[:message_id]
        workspace.adapter.mark_escalation_dm_acknowledged(channel_id: channel_id, message_id: pressed[:message_id], original_blocks: pressed[:content])
      end

      nil
    rescue JSON::ParserError, ActiveRecord::RecordNotFound
      nil
    end
  end
end
