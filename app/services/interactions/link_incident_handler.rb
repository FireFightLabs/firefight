module Interactions
  class LinkIncidentHandler
    def self.execute(interaction)
      workspace = interaction.workspace
      incident_id = interaction.private_metadata
      incident = workspace.incidents.find(incident_id)
      member = workspace.workspace_memberships.find_by!(platform_user_id: interaction.user_id)

      relationship_type = interaction.values.dig("relationship_type_block", "relationship_type_select", "selected_option", "value")
      target_id = interaction.values.dig("target_incident_block", "target_incident_select", "selected_option", "value")
      target = workspace.incidents.find(target_id)

      service = IncidentRelationshipService.new(workspace)

      case relationship_type
      when IncidentRelationship::RELATED
        service.link_related(source: incident, target: target, created_by: member)
        IncidentLinkWorkflow.start!(incident, context: {
          linked_by_platform_user_id: interaction.user_id,
          target_incident_id: target.id,
          relationship_type: IncidentRelationship::RELATED
        })
      when IncidentRelationship::DUPLICATE
        service.mark_duplicate(source: incident, canonical: target, created_by: member)
        IncidentLinkWorkflow.start!(incident, context: {
          linked_by_platform_user_id: interaction.user_id,
          target_incident_id: target.id,
          relationship_type: IncidentRelationship::DUPLICATE
        })
      end

      nil
    rescue ActiveRecord::RecordNotFound => e
      Rails.logger.warn({ event: "interactions.link_incident.record_not_found", error: e.message })
      error_msg = if e.message.include?("canceled status")
        "Your workspace doesn't have a canceled status configured. Please add one before marking duplicates."
      else
        "Something went wrong. Please close this modal and try again."
      end
      { response_action: "errors", errors: { "target_incident_block" => error_msg } }
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.warn({ event: "interactions.link_incident.invalid", error: e.message })
      { response_action: "errors", errors: { "target_incident_block" => e.record.errors.full_messages.join(", ") } }
    end
  end
end
