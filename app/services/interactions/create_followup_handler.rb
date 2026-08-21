module Interactions
  class CreateFollowupHandler
    extend HandlerAuthorization
    authorize_as ApiKey::RESOURCE_INCIDENTS, ApiKey::ACTION_UPDATE

    def self.execute(interaction)
      workspace = interaction.workspace
      metadata = parse_metadata(interaction.private_metadata)
      incident = workspace.incidents.find(metadata[:incident_id])
      member = workspace.workspace_memberships.find_by!(platform_user_id: interaction.user_id)

      description = interaction.values.dig("description_block", "description_input", "value")
      assignee_user_id = interaction.values.dig("assignee_block", "assignee_select", "selected_user")
      if assignee_user_id
        assignee = WorkspaceMemberProvisioner.find_or_provision!(
          workspace: workspace,
          platform_user_id: assignee_user_id,
          adapter: workspace.adapter
        )
        return { response_action: "errors", errors: { "assignee_block" => "Couldn't load that user's profile from Slack. Please try again in a moment." } } unless assignee
      end

      platform_data = {}
      platform_data[:source_message_link] = metadata[:source_message_link] if metadata[:source_message_link]

      IncidentActionService.new(workspace).create_action(
        incident: incident,
        created_by: member,
        action_type: IncidentAction::ACTION_TYPE_FOLLOWUP,
        description: description,
        assignee: assignee,
        platform_data: platform_data
      )

      { response_action: "clear" }
    rescue ActiveRecord::RecordNotFound => e
      Rails.logger.warn({ event: "interactions.create_followup.record_not_found", error: e.message })
      { response_action: "errors", errors: { "description_block" => "Something went wrong. Please close this modal and try again." } }
    end

    def self.parse_metadata(raw)
      parsed = JSON.parse(raw)
      {
        incident_id: parsed["incident_id"],
        source_message_text: parsed["source_message_text"],
        source_message_link: parsed["source_message_link"]
      }
    rescue JSON::ParserError
      { incident_id: raw }
    end
    private_class_method :parse_metadata
  end
end
