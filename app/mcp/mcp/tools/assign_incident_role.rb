module Mcp
  module Tools
    class AssignIncidentRole < Base
      tool_name ASSIGN_INCIDENT_ROLE
      authorize_as ApiKey::RESOURCE_INCIDENTS, ApiKey::ACTION_UPDATE
      description "Assign an incident role to one person, or clear it. A role names who is " \
                  "accountable, so each role has a single holder and assigning replaces whoever " \
                  "held it. Identify the person by email or platform user id; omit member to " \
                  "clear the role. Call get_incident for the roles this workspace configured and " \
                  "who holds them. If the call requires approval, retry the identical call with " \
                  "approval_id once approved. Docs: #{Docs::INCIDENTS}"
      annotations(**WRITE)
      input_schema(
        properties: {
          incident: { type: "string", description: "Incident UUID or identifier like INC-42" },
          role: { type: "string", description: "Incident role slug, e.g. incident_lead" },
          member: { type: "string", description: "Email or platform user id of the person; omit to clear the role" },
          approval_id: { type: "string", description: "Approval id when retrying an approved call" }
        },
        required: [ "incident", "role" ]
      )

      def self.perform_with_principal(workspace:, principal:, args:)
        incident = GetIncident.find_by_reference(workspace.incidents.where(deleted_at: nil), args[:incident].to_s)
        raise ActiveRecord::RecordNotFound unless incident

        role = workspace.incident_roles.active.find_by(slug: args[:role].to_s)
        return unknown_role_error(workspace, args[:role]) unless role

        requested_member = args[:member].to_s
        member = requested_member.present? ? find_member(workspace, requested_member) : nil

        return unknown_member_error(requested_member) if requested_member.present? && member.nil?
        return Mcp::ToolDispatcher.error_response(role.unassign_blocked_reason) if member.nil? && role.unassign_blocked_reason

        IncidentLifecycleService.new(workspace).assign_role(incident, role, member, changed_by: principal)

        respond(
          incident: incident.identifier,
          role: role.slug,
          role_name: role.name,
          member: member&.display_name,
          assigned: member.present?
        )
      end

      def self.find_member(workspace, reference)
        workspace.workspace_memberships.resolve(reference)
      end
      private_class_method :find_member

      def self.unknown_role_error(workspace, requested)
        available = workspace.incident_roles.active.ordered.pluck(:slug)
        Mcp::ToolDispatcher.error_response(
          "Unknown incident role #{requested.inspect}. This workspace has: #{available.join(', ')}."
        )
      end
      private_class_method :unknown_role_error

      def self.unknown_member_error(requested)
        Mcp::ToolDispatcher.error_response(
          "No workspace member matches #{requested.inspect}. Pass the email they sign in with, or their platform user id."
        )
      end
      private_class_method :unknown_member_error
    end
  end
end
