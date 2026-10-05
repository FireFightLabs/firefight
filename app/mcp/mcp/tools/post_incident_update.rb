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
                  "required. A required answer left out keeps what the incident already has, so " \
                  "send only what changes. Write message as markdown with real line breaks: a lead " \
                  "sentence, then a blank line and one \"- \" bullet per point when there is more than " \
                  "one, with links as plain URLs or [text](url). Never run several points together on " \
                  "one line and never type bullet characters such as •, because the dashboard and the " \
                  "incident channel draw the list from the line breaks. If the call requires approval, " \
                  "retry the identical call with approval_id once approved. Docs: #{Docs::INCIDENTS}"
      annotations(**WRITE)
      input_schema(
        properties: {
          incident: { type: "string", description: "Incident UUID or identifier like INC-42" },
          answers: {
            type: "object",
            description: "The update form's answers, keyed by the field keys get_form returned, " \
                         "e.g. { \"message\": \"Rolled back the 14:02 deploy.\\n\\n- Errors are back to baseline\\n- " \
                         "Watching for 30 minutes\", \"status\": \"monitoring\" }"
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
