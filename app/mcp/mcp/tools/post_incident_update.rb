module Mcp
  module Tools
    class PostIncidentUpdate < Base
      tool_name POST_INCIDENT_UPDATE
      authorize_as Ability::Action::RESOURCE_INCIDENTS, Ability::Action::ACTION_UPDATE
      description "Post an update on an incident: what you have found, what you are doing, and where " \
                  "the incident stands now. This is how you tell the responders in the channel what " \
                  "is happening, so use it whenever you learn something or change something. It can " \
                  "also move status, severity and type in the same call. Call get_form with " \
                  "form: \"update\" first, since this workspace decides what is asked and what is " \
                  "required. If the call requires approval, retry the identical call with " \
                  "approval_id once approved. Docs: #{Docs::INCIDENTS}"
      annotations(**WRITE)
      input_schema(
        properties: {
          incident: { type: "string", description: "Incident UUID or identifier like INC-42" },
          answers: {
            type: "object",
            description: "The update form's answers, keyed by the field keys get_form returned, " \
                         "e.g. { \"message\": \"Rolled back the 14:02 deploy\", \"status\": \"monitoring\" }"
          },
          approval_id: { type: "string", description: "Approval id when retrying an approved call" }
        },
        required: [ "incident", "answers" ]
      )

      def self.perform_with_principal(workspace:, principal:, args:)
        IncidentWrite.submit_form(
          workspace, principal, args, form_slug: IncidentForm::SLUG_UPDATE
        ) { |incident| { updated: true }.merge(SearchIncidents.summary(incident)) }
      end
    end
  end
end
