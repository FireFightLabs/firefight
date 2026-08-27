module Mcp
  module Tools
    class DismissTimelineNote < Base
      tool_name DISMISS_TIMELINE_NOTE
      authorize_as Ability::Action::RESOURCE_INCIDENTS, Ability::Action::ACTION_UPDATE
      description "Dismiss one AI-noted milestone from an incident's timeline, for when the note " \
                  "reads a joke as a decision or credits the wrong person. The note is kept and " \
                  "marked dismissed rather than deleted, and stops being returned as a timeline " \
                  "event. Get note ids from get_incident. If the call requires approval, retry the " \
                  "identical call with approval_id once approved. Docs: #{Docs::INCIDENTS}"
      annotations(**WRITE)
      input_schema(
        properties: {
          incident: { type: "string", description: "Incident UUID or identifier like INC-42" },
          note_id: { type: "string", description: "UUID of the milestone.noted timeline event to dismiss" },
          approval_id: { type: "string", description: "Approval id when retrying an approved call" }
        },
        required: [ "incident", "note_id" ]
      )

      def self.perform_with_principal(workspace:, principal:, args:)
        incident = GetIncident.find_by_reference(workspace.incidents.where(deleted_at: nil), args[:incident].to_s)
        raise ActiveRecord::RecordNotFound unless incident

        note = incident.incident_events.find_by!(id: args[:note_id].to_s)
        note.dismiss!(by: principal)

        respond(
          incident: incident.identifier,
          note_id: note.id,
          statement: note.metadata.to_h["statement"],
          dismissed: true
        )
      rescue IncidentEvent::NotDismissable => e
        Mcp::ToolDispatcher.error_response(e.message)
      end
    end
  end
end
