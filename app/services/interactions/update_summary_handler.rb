module Interactions
  class UpdateSummaryHandler
    def self.execute(interaction)
      workspace = interaction.workspace
      metadata = parse_metadata(interaction.private_metadata)
      incident = workspace.incidents.find(metadata[:incident_id])
      member = workspace.workspace_memberships.find_by!(platform_user_id: interaction.user_id)
      new_summary = interaction.values.dig("summary_block", "summary_input", "value")

      incident.record_change!(IncidentEvent::INCIDENT_UPDATED, changed_by: member) do
        incident.update!(summary: new_summary)
      end

      SummaryUpdateWorkflow.start!(incident, context: {
        updated_by_platform_user_id: interaction.user_id
      })

      delete_temp_message(workspace, metadata)

      nil
    rescue ActiveRecord::RecordNotFound => e
      Rails.logger.warn({ event: "interactions.update_summary.record_not_found", error: e.message })
      delete_temp_message(workspace, metadata) if workspace && metadata
      { response_action: "errors", errors: { "summary_block" => "Something went wrong. Please close this modal and try again." } }
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

      workspace.adapter.delete_message(channel_id: metadata[:channel_id], message_id: metadata[:temp_message_ts])
    rescue AdapterError => e
      Rails.logger.warn({ event: "interactions.update_summary.delete_temp_failed", error: e.message })
    end
    private_class_method :delete_temp_message
  end
end
