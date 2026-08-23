module Interactions
  class AcknowledgeEscalationHandler
    extend HandlerAuthorization
    authorize_as ApiKey::RESOURCE_INCIDENTS, ApiKey::ACTION_UPDATE

    def self.execute(interaction)
      workspace = interaction.workspace
      payload = JSON.parse(interaction.action_value || "{}")
      incident = workspace.incidents.find(payload["incident_id"])
      escalation_event = incident.incident_events.find(payload["escalation_event_id"])
      escalated_to_platform_user_id = escalation_event.metadata["escalated_to_platform_user_id"]

      return nil unless escalated_to_platform_user_id == interaction.user_id
      return nil if escalation_event.escalation_acknowledged?

      escalation_event.update!(
        metadata: escalation_event.metadata.deep_stringify_keys.merge(
          "acknowledged_by_platform_user_id" => interaction.user_id,
          "acknowledged_at" => Time.current.iso8601
        )
      )

      incident.incident_events.create!(
        event_type: IncidentEvent::ESCALATION_ACKNOWLEDGED,
        metadata: {
          escalation_event_id: escalation_event.id,
          acknowledged_by_platform_user_id: interaction.user_id,
          escalated_to_platform_user_id: escalated_to_platform_user_id
        }
      )

      IncidentUpdateService.new(workspace).post_escalation_acknowledged_message(
        incident,
        acknowledged_by_platform_user_id: interaction.user_id,
        escalated_to_platform_user_id: escalated_to_platform_user_id
      )

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
