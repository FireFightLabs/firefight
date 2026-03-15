module Interactions
  class CloseIncidentHandler
    def self.execute(interaction)
      workspace = interaction.workspace
      metadata = parse_metadata(interaction.private_metadata)
      incident = workspace.incidents.find(metadata[:incident_id])
      member = workspace.workspace_memberships.find_by!(platform_user_id: interaction.user_id)

      return already_closed_error if incident.closed?

      new_name = interaction.values.dig("name_block", "name_input", "value")
      new_summary = interaction.values.dig("summary_block", "summary_input", "value")
      severity_slug = interaction.values.dig("severity_block", "severity_select", "selected_option", "value")
      lead_user_id = interaction.values.dig("lead_block", "lead_select", "selected_user")

      resolved_status = workspace.incident_statuses.closed.first
      new_severity = workspace.incident_severities.active.find_by!(slug: severity_slug)

      incident.record_change!(IncidentEvent::INCIDENT_RESOLVED, changed_by: member) do
        attrs = { incident_status: resolved_status, incident_severity: new_severity }
        attrs[:name] = new_name if new_name.present?
        attrs[:summary] = new_summary if new_summary.present?
        incident.update!(attrs)

        if lead_user_id.present?
          lead_member = workspace.workspace_memberships.find_by!(platform_user_id: lead_user_id)
          incident.lead = lead_member
        end
      end

      IncidentTranscriptCache.expire_after_close!(incident)

      IncidentCloseWorkflow.start!(incident, context: {
        resolved_by_platform_user_id: interaction.user_id
      })

      delete_temp_message(workspace, metadata)

      nil
    rescue ActiveRecord::RecordNotFound => e
      Rails.logger.warn({ event: "interactions.close_incident.record_not_found", error: e.message })
      delete_temp_message(workspace, metadata) if workspace && metadata
      { response_action: "errors", errors: { "summary_block" => "Something went wrong. Please close this modal and try again." } }
    end

    def self.parse_metadata(raw)
      parsed = JSON.parse(raw)
      { incident_id: parsed.fetch("incident_id"), temp_message_ts: parsed["temp_message_ts"].to_s, channel_id: parsed["channel_id"].to_s }
    rescue JSON::ParserError, KeyError => e
      raise "Invalid modal metadata: #{e.message}"
    end
    private_class_method :parse_metadata

    def self.already_closed_error
      { response_action: "errors", errors: { "summary_block" => "This incident is already closed." } }
    end
    private_class_method :already_closed_error

    def self.delete_temp_message(workspace, metadata)
      return unless metadata[:temp_message_ts] && metadata[:channel_id]

      adapter = WorkspaceAdapter.for(workspace)
      adapter.delete_message(channel_id: metadata[:channel_id], ts: metadata[:temp_message_ts])
    rescue AdapterError => e
      Rails.logger.warn({ event: "interactions.close_incident.delete_temp_failed", error: e.message })
    end
    private_class_method :delete_temp_message
  end
end
