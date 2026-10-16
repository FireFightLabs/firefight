module Interactions
  class LinkIncidentHandler
    extend HandlerAuthorization
    authorize_as Ability::Action::RESOURCE_INCIDENTS, Ability::Action::ACTION_UPDATE

    def self.execute(interaction)
      workspace = interaction.workspace
      incident = workspace.incidents.find(interaction.metadata.incident_id)
      member = workspace.workspace_memberships.find_by!(platform_user_id: interaction.user_id)

      relationship_type = workspace.adapter.submitted_value(values: interaction.values, block_id: Identifiers::RELATIONSHIP_TYPE_BLOCK, input_id: Identifiers::RELATIONSHIP_TYPE_SELECT, kind: PlatformAdapter::Input::OPTION)
      target_id = workspace.adapter.submitted_value(values: interaction.values, block_id: Identifiers::TARGET_INCIDENT_BLOCK, input_id: Identifiers::TARGET_INCIDENT_SELECT, kind: PlatformAdapter::Input::OPTION)
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
        Interactions::ModalCleanup::RECORD_GONE
      end
      workspace.adapter.modal_errors_response({ Identifiers::TARGET_INCIDENT_BLOCK => error_msg })
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.warn({ event: "interactions.link_incident.invalid", error: e.message })
      workspace.adapter.modal_errors_response({ Identifiers::TARGET_INCIDENT_BLOCK => e.record.errors.full_messages.join(", ") })
    end
  end
end
