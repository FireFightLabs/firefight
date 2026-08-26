module Mcp
  module Tools
    class DeclareIncident < Base
      tool_name DECLARE_INCIDENT
      authorize_as Ability::Action::RESOURCE_INCIDENTS, Ability::Action::ACTION_CREATE
      description "Declare a new incident. Firefight opens a channel for it and announces it, the same " \
                  "as a person running /ff new. Call get_form with form: \"declare\" first: this " \
                  "workspace decides which fields are asked and which are required, custom ones " \
                  "included, and this tool refuses anything that form does not ask for. Pass the " \
                  "answers keyed exactly as get_form names them. If the call requires approval, retry " \
                  "the identical call with approval_id once approved. Docs: #{Docs::INCIDENTS}"
      annotations(**WRITE)
      input_schema(
        properties: {
          answers: {
            type: "object",
            description: "The declare form's answers, keyed by the field keys get_form returned, " \
                         "e.g. { \"name\": \"Checkout failing\", \"severity\": \"critical\" }"
          },
          approval_id: { type: "string", description: "Approval id when retrying an approved call" }
        },
        required: [ "answers" ]
      )

      def self.perform_with_principal(workspace:, principal:, args:)
        answers = (args[:answers] || {}).to_h.stringify_keys
        submission = Mcp::Tools::FormAnswers.validate!(
          workspace, incident: nil, form_slug: IncidentForm::SLUG_DECLARE, answers: answers
        )

        incident = IncidentLifecycleService.new(workspace).create(
          **submission.creation_attributes,
          declared_by: principal,
          source: Incident::SOURCE_MCP
        )

        respond(SearchIncidents.summary(incident).merge(declared: true))
      rescue IncidentFormResolver::ValidationError => e
        Mcp::ToolDispatcher.error_response(
          "#{e.field_errors.join('; ')}. Call get_form with form: \"declare\" for what this workspace asks."
        )
      end
    end
  end
end
