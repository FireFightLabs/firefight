module Mcp
  module Tools
    # Validating a form submission is the same three steps wherever it arrives
    # from, and the context has to be the one the fields were resolved against
    # or a field the agent's own answers brought into scope is refused.
    module FormAnswers
      def self.validate!(workspace, incident:, form_slug:, answers:)
        context = IncidentFormPrompt.new(
          workspace, incident: incident, form_slug: form_slug, answers: answers
        ).context

        validated = IncidentFormResolver.new(workspace).validate_submission!(form_slug, answers, context: context)

        IncidentFormSubmission.new(
          workspace,
          incident: incident,
          form_slug: form_slug,
          system_attrs: validated[:system_attrs],
          custom_fields: validated[:custom_fields],
          visible_system_keys: validated[:visible_system_keys]
        )
      end
    end
  end
end
