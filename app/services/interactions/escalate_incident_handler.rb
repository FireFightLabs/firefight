module Interactions
  class EscalateIncidentHandler
    def self.execute(interaction)
      workspace = interaction.workspace
      metadata = parse_metadata(interaction.private_metadata)
      incident = workspace.incidents.find(metadata[:incident_id])
      member = workspace.workspace_memberships.find_by!(platform_user_id: interaction.user_id)

      escalated_to_user_id = interaction.values.dig("escalate_to_block", "escalate_to_select", "selected_user")
      reason = interaction.values.dig("reason_block", "reason_input", "value")

      escalation_event = incident.incident_events.create!(
        event_type: IncidentEvent::INCIDENT_ESCALATED,
        user: member,
        metadata: {
          details: {
            escalated_to_platform_user_id: escalated_to_user_id,
            reason: reason
          }
        }
      )

      IncidentEscalationWorkflow.start!(incident, context: {
        escalated_by_platform_user_id: interaction.user_id,
        escalated_to_platform_user_id: escalated_to_user_id,
        escalation_event_id: escalation_event.id,
        reason: reason
      })

      EscalationAcknowledgementReminderJob.set(wait: 10.minutes).perform_later(
        incident.id,
        escalation_event.id,
        interaction.user_id,
        escalated_to_user_id,
        reason
      )

      delete_temp_message(workspace, metadata)

      nil
    rescue ActiveRecord::RecordNotFound => e
      Rails.logger.warn({ event: "interactions.escalate_incident.record_not_found", error: e.message })
      delete_temp_message(workspace, metadata) if workspace && metadata
      { response_action: "errors", errors: { "escalate_to_block" => "Something went wrong. Please close this modal and try again." } }
    end

    def self.parse_metadata(raw)
      parsed = JSON.parse(raw)
      { incident_id: parsed["incident_id"], temp_message_ts: parsed["temp_message_ts"], channel_id: parsed["channel_id"] }
    rescue JSON::ParserError
      { incident_id: raw }
    end
    private_class_method :parse_metadata

    def self.delete_temp_message(workspace, metadata)
      return unless metadata[:temp_message_ts] && metadata[:channel_id]

      adapter = WorkspaceAdapter.for(workspace)
      adapter.delete_message(channel_id: metadata[:channel_id], ts: metadata[:temp_message_ts])
    rescue AdapterError => e
      Rails.logger.warn({ event: "interactions.escalate_incident.delete_temp_failed", error: e.message })
    end
    private_class_method :delete_temp_message
  end
end
