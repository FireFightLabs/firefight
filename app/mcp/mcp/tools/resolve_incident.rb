module Mcp
  module Tools
    class ResolveIncident < Base
      tool_name RESOLVE_INCIDENT
      authorize_as Ability::Action::RESOURCE_INCIDENTS, Ability::Action::ACTION_UPDATE
      description "Resolve an incident, meaning the response is over and this was a real incident. " \
                  "Closing it is what makes a postmortem available. Call get_form with " \
                  "form: \"resolve\" first for what this workspace asks. Use cancel_incident instead " \
                  "when it turned out not to be an incident. If the call requires approval, retry the " \
                  "identical call with approval_id once approved. Docs: #{Docs::INCIDENTS}"
      annotations(**WRITE)
      input_schema(
        properties: {
          incident: { type: "string", description: "Incident UUID or identifier like INC-42" },
          answers: { type: "object", description: "The resolve form's answers, keyed as get_form returned them" },
          approval_id: { type: "string", description: "Approval id when retrying an approved call" }
        },
        required: [ "incident" ]
      )

      def self.perform_with_principal(workspace:, principal:, args:)
        IncidentWrite.submit_form(
          workspace, principal, args, form_slug: IncidentForm::SLUG_RESOLVE
        ) { |incident| { resolved: true }.merge(SearchIncidents.summary(incident)) }
      end
    end
  end
end
