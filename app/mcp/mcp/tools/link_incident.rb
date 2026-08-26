module Mcp
  module Tools
    class LinkIncident < Base
      tool_name LINK_INCIDENT
      authorize_as Ability::Action::RESOURCE_INCIDENTS, Ability::Action::ACTION_UPDATE
      description "Connect two incidents. relationship \"related\" records the link on both " \
                  "timelines and changes nothing else. relationship \"duplicate\" also cancels " \
                  "this incident, naming the one that absorbed it, so use it only when this " \
                  "incident is the same event seen twice. A closed incident has to be reopened " \
                  "first. If the call requires approval, retry the identical call with " \
                  "approval_id once approved. Docs: #{Docs::INCIDENTS}"
      annotations(**WRITE)
      input_schema(
        properties: {
          incident: { type: "string", description: "Incident UUID or identifier like INC-42" },
          other_incident: { type: "string", description: "The incident to link to, UUID or identifier" },
          relationship: {
            type: "string",
            enum: [ IncidentRelationship::RELATED, IncidentRelationship::DUPLICATE ],
            description: "related leaves both open; duplicate cancels this incident into the other"
          },
          approval_id: { type: "string", description: "Approval id when retrying an approved call" }
        },
        required: [ "incident", "other_incident", "relationship" ]
      )

      def self.perform_with_principal(workspace:, principal:, args:)
        incident = IncidentWrite.find!(workspace, args[:incident])
        other = IncidentWrite.find!(workspace, args[:other_incident])

        service = IncidentRelationshipService.new(workspace)
        duplicate = args[:relationship].to_s == IncidentRelationship::DUPLICATE

        if duplicate
          service.mark_duplicate(source: incident, canonical: other, created_by: principal)
        else
          service.link_related(source: incident, target: other, created_by: principal)
        end

        respond(
          incident: incident.identifier,
          other_incident: other.identifier,
          relationship: args[:relationship].to_s,
          status: incident.reload.incident_status.name
        )
      end
    end
  end
end
