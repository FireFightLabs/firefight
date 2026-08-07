module Mcp
  module Tools
    class AttachRunbook < Base
      tool_name ATTACH_RUNBOOK
      authorize_as ApiKey::RESOURCE_INCIDENTS, ApiKey::ACTION_UPDATE
      description "Attach a runbook to an incident, posting its steps in the incident channel " \
                  "for responders to claim. Runbooks whose conditions match attach on their " \
                  "own, so this is for the ones that do not. Attaching twice is a no-op. Call " \
                  "search_runbooks for the slugs available. If the call requires approval, " \
                  "retry the identical call with approval_id once approved. Docs: #{Docs::RUNBOOKS}"
      annotations(**WRITE)
      input_schema(
        properties: {
          incident: { type: "string", description: "Incident UUID or identifier like INC-42" },
          runbook: { type: "string", description: "Runbook slug" },
          approval_id: { type: "string", description: "Approval id when retrying an approved call" }
        },
        required: [ "incident", "runbook" ]
      )

      def self.perform_with_principal(workspace:, principal:, args:)
        incident = GetIncident.find_by_reference(workspace.incidents.where(deleted_at: nil), args[:incident].to_s)
        raise ActiveRecord::RecordNotFound unless incident

        attached_by = principal if principal.is_a?(WorkspaceMembership)
        already_attached = incident.incident_runbooks.joins(:runbook).exists?(runbooks: { slug: args[:runbook].to_s })

        incident_runbook = RunbookAttachmentService.new(workspace).attach_by_slug(
          incident: incident, slug: args[:runbook], attached_by: attached_by
        )
        runbook = incident_runbook.runbook

        respond(
          incident: incident.identifier,
          runbook: runbook.slug,
          name: runbook.name,
          steps_count: runbook.runbook_steps.size,
          newly_attached: !already_attached
        )
      end
    end
  end
end
