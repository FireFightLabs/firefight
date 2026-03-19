module Interactions
  class ReopenIncidentHandler
    def self.execute(interaction)
      workspace = interaction.workspace
      metadata = parse_metadata(interaction.private_metadata)
      incident = workspace.incidents.find(metadata[:incident_id])
      member = workspace.workspace_memberships.find_by!(platform_user_id: interaction.user_id)

      return already_active_error unless incident.closed?

      reason = interaction.values.dig("reason_block", "reason_input", "value")
      default_status = workspace.incident_statuses.live.find_by(is_default: true) || workspace.incident_statuses.live.first

      incident.record_change!(IncidentEvent::INCIDENT_REOPENED, changed_by: member, message: reason, details: { reason: reason }) do
        incident.update!(incident_status: default_status)
      end

      IncidentTranscriptCache.clear_expiry!(incident)

      if incident.channel_archived_at.present?
        workspace.adapter.unarchive_channel(channel_id: incident.channel_id)
        incident.update!(channel_archived_at: nil, channel_archived_by: nil)
      end

      IncidentReopenWorkflow.start!(incident, context: {
        reopened_by_platform_user_id: interaction.user_id,
        reason: reason
      })

      delete_temp_message(workspace, metadata)

      nil
    rescue ActiveRecord::RecordNotFound => e
      Rails.logger.warn({ event: "interactions.reopen_incident.record_not_found", error: e.message })
      delete_temp_message(workspace, metadata) if workspace && metadata
      { response_action: "errors", errors: { "reason_block" => "Something went wrong. Please close this modal and try again." } }
    end

    def self.parse_metadata(raw)
      parsed = JSON.parse(raw)
      { incident_id: parsed["incident_id"], temp_message_ts: parsed["temp_message_ts"], channel_id: parsed["channel_id"] }
    rescue JSON::ParserError
      { incident_id: raw }
    end
    private_class_method :parse_metadata

    def self.already_active_error
      { response_action: "errors", errors: { "reason_block" => "This incident is already active." } }
    end
    private_class_method :already_active_error

    def self.delete_temp_message(workspace, metadata)
      return unless metadata[:temp_message_ts] && metadata[:channel_id]

      workspace.adapter.delete_message(channel_id: metadata[:channel_id], ts: metadata[:temp_message_ts])
    rescue AdapterError => e
      Rails.logger.warn({ event: "interactions.reopen_incident.delete_temp_failed", error: e.message })
    end
    private_class_method :delete_temp_message
  end
end
