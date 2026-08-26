module Mcp
  module Tools
    class CancelIncident < Base
      tool_name CANCEL_INCIDENT
      authorize_as Ability::Action::RESOURCE_INCIDENTS, Ability::Action::ACTION_UPDATE
      description "Cancel an incident, meaning it turned out not to be one: a false positive, a " \
                  "duplicate, or a mistake. It keeps its channel and timeline but never counts as " \
                  "resolved and gets no postmortem. Use resolve_incident for something that was real. " \
                  "Call get_form with form: \"cancel\" first for what this workspace asks. If the " \
                  "call requires approval, retry the identical call with approval_id once approved. " \
                  "Docs: #{Docs::INCIDENTS}"
      annotations(**WRITE)
      input_schema(
        properties: {
          incident: { type: "string", description: "Incident UUID or identifier like INC-42" },
          answers: { type: "object", description: "The cancel form's answers, keyed as get_form returned them" },
          approval_id: { type: "string", description: "Approval id when retrying an approved call" }
        },
        required: [ "incident" ]
      )

      def self.perform_with_principal(workspace:, principal:, args:)
        IncidentWrite.submit_form(
          workspace, principal, args, form_slug: IncidentForm::SLUG_CANCEL
        ) { |incident| { canceled: true }.merge(SearchIncidents.summary(incident)) }
      end
    end
  end
end
