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

      dm_channel_id = interaction.raw&.dig("container", "channel_id") || interaction.channel_id
      dm_message_ts = interaction.raw&.dig("container", "message_ts")

      if dm_channel_id && dm_message_ts
        workspace.adapter.mark_escalation_dm_acknowledged(
          channel_id: dm_channel_id,
          message_id: dm_message_ts,
          original_blocks: interaction.raw&.dig("message", "blocks") || []
        )
      end

      nil
    rescue JSON::ParserError, ActiveRecord::RecordNotFound
      nil
    end
  end
end
