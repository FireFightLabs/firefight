module Interactions
  class AcknowledgeEscalationHandler
    def self.execute(interaction)
      workspace = interaction.workspace
      payload = JSON.parse(interaction.action_value || "{}")
      incident = workspace.incidents.find(payload["incident_id"])
      escalation_event = incident.incident_events.find(payload["escalation_event_id"])
      details = escalation_event.details || {}
      escalated_to_platform_user_id = details["escalated_to_platform_user_id"]

      return nil unless escalated_to_platform_user_id == interaction.user_id

      EscalationAcknowledgementTracker.mark_acknowledged!(
        workspace_id: workspace.id,
        escalation_event_id: escalation_event.id
      )

      metadata = escalation_event.metadata.deep_stringify_keys
      detail_data = metadata["details"] || {}
      escalation_event.update!(
        metadata: {
          **metadata,
          "details" => {
            **detail_data,
            "acknowledged_by_platform_user_id" => interaction.user_id,
            "acknowledged_at" => Time.current.iso8601
          }
        }
      )

      incident.incident_events.create!(
        event_type: IncidentEvent::ESCALATION_ACKNOWLEDGED,
        metadata: {
          details: {
            escalation_event_id: escalation_event.id,
            acknowledged_by_platform_user_id: interaction.user_id,
            escalated_to_platform_user_id: escalated_to_platform_user_id
          }
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
        original_blocks = interaction.raw&.dig("message", "blocks") || []
        updated_blocks = original_blocks.reject { |b| b["type"] == "actions" }
        updated_blocks << {
          type: "section",
          text: { type: "mrkdwn", text: ":white_check_mark: *You acknowledged this escalation*" }
        }

        workspace.adapter.update_message(
          channel_id: dm_channel_id,
          ts: dm_message_ts,
          text: "Escalation acknowledged",
          blocks: updated_blocks
        )
      end

      nil
    rescue JSON::ParserError, ActiveRecord::RecordNotFound
      nil
    end
  end
end
