module Interactions
  class IncidentUpdateHandler
    def self.execute(interaction)
      workspace = interaction.workspace
      metadata = parse_metadata(interaction.private_metadata)
      incident = workspace.incidents.find(metadata[:incident_id])
      member = workspace.workspace_memberships.find_by!(platform_user_id: interaction.user_id)

      status_slug = interaction.values.dig("status_block", "status_select", "selected_option", "value")
      severity_slug = interaction.values.dig("severity_block", "severity_select", "selected_option", "value")
      message = interaction.values.dig("message_block", "message_input", "value")
      next_update_minutes = interaction.values.dig("next_update_block", "next_update_select", "selected_option", "value")

      new_status = workspace.incident_statuses.active.find_by!(slug: status_slug)
      new_severity = workspace.incident_severities.active.find_by!(slug: severity_slug)

      previous_status_name = incident.incident_status.name
      previous_severity_name = incident.incident_severity.name

      incident.record_change!(IncidentEvent::INCIDENT_UPDATED, changed_by: member, message: message) do
        incident.update!(
          incident_status: new_status,
          incident_severity: new_severity
        )
      end

      if next_update_minutes.present?
        incident.update!(next_update_at: Time.current + next_update_minutes.to_i.minutes)
        IncidentUpdateReminderJob.set(wait: next_update_minutes.to_i.minutes).perform_later(incident.id, incident.next_update_at.iso8601)
      else
        incident.update!(next_update_at: nil)
      end

      IncidentUpdateWorkflow.start!(incident, context: {
        updated_by_platform_user_id: interaction.user_id,
        message: message,
        previous_status_name: previous_status_name,
        previous_severity_name: previous_severity_name
      })

      delete_temp_message(workspace, metadata)

      nil
    rescue ActiveRecord::RecordNotFound => e
      Rails.logger.warn({ event: "interactions.incident_update.record_not_found", error: e.message })
      delete_temp_message(workspace, metadata) if workspace && metadata
      { response_action: "errors", errors: { "status_block" => "Something went wrong. Please close this modal and try again." } }
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
      Rails.logger.warn({ event: "interactions.incident_update.delete_temp_failed", error: e.message })
    end
    private_class_method :delete_temp_message
  end
end
