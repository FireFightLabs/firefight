module Mcp
  module Tools
    # The shape every incident-write tool shares: find the incident, validate
    # the answers against the form this workspace configured, hand them to the
    # lifecycle service, report what the incident looks like now.
    module IncidentWrite
      def self.find!(workspace, reference)
        incident = GetIncident.find_by_reference(workspace.incidents.where(deleted_at: nil), reference.to_s)
        raise ActiveRecord::RecordNotFound unless incident

        incident
      end

      def self.submit_form(workspace, principal, args, form_slug:)
        incident = find!(workspace, args[:incident])
        answers = (args[:answers] || {}).to_h.stringify_keys

        submission = FormAnswers.validate!(
          workspace, incident: incident, form_slug: form_slug, answers: answers
        )

        attrs = submission.attributes
        attrs[:lead] = workspace.workspace_memberships.resolve!(submission.lead_value) if submission.lead_value

        IncidentLifecycleService.new(workspace).change_status(
          incident, attrs, changed_by: principal, message: submission.message
        )

        payload = yield(incident.reload)
        ::MCP::Tool::Response.new(
          [ { type: "text", text: JSON.pretty_generate(payload) } ],
          structured_content: payload
        )
      rescue IncidentFormResolver::ValidationError => e
        Mcp::ToolDispatcher.error_response(
          "#{e.field_errors.join('; ')}. Call get_form with form: \"#{form_slug}\" for what this workspace asks."
        )
      rescue Incident::NotActive => e
        Mcp::ToolDispatcher.error_response(e.message)
      end
    end
  end
end
