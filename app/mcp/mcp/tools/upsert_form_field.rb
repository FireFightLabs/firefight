module Mcp
  module Tools
    class UpsertFormField < Base
      tool_name UPSERT_FORM_FIELD
      description "Configure one field on a lifecycle form: attach a custom field, or change " \
                  "the visibility, required mode, or conditions of a field already there. " \
                  "Identify the field by custom_field key or system_field key. Conditions make " \
                  "the field appear only when they match, and values accept slugs or ids. " \
                  "Severity and Status cannot be hidden or made optional. If the call requires " \
                  "approval, retry the identical call with approval_id once approved. " \
                  "Docs: #{Docs::INCIDENT_FORMS}"
      annotations(**WRITE)
      input_schema(
        properties: {
          form: {
            type: "string",
            description: "Form slug, one of: #{IncidentForm::SLUGS.join(', ')}"
          },
          custom_field: { type: "string", description: "Custom field key, for a workspace-defined field" },
          system_field: {
            type: "string",
            description: "System field key, one of: #{IncidentSystemField::DEFINITIONS.map(&:key).join(', ')}"
          },
          visible: { type: "boolean", description: "Whether responders see the field, default true" },
          required: { type: "boolean", description: "Whether the field must be filled in, default false" },
          conditions: {
            type: "array",
            description: "Show the field only when these match, e.g. " \
                         "[{\"condition_field\": \"incident_type\", \"operator\": \"one_of\", \"values\": [\"production\"]}]. " \
                         "A custom_field condition names its field too, e.g. [{\"condition_field\": \"custom_field\", " \
                         "\"custom_field\": \"affected_service\", \"operator\": \"one_of\", \"values\": [\"checkout\"]}]. " \
                         "Values accept ids or names: a severity or incident_type slug, an option label for a fixed list, " \
                         "a catalog entry slug for a catalog-backed field. Replaces existing conditions, pass [] to clear them",
            items: { type: "object" }
          },
          approval_id: { type: "string", description: "Approval id when retrying an approved call" }
        },
        required: [ "form" ]
      )

      def self.authorization(_workspace, _args)
        [ Ability::Action::RESOURCE_FORMS, Ability::Action::ACTION_UPDATE ]
      end

      def self.perform(workspace:, args:)
        form, form_field = IncidentFormService.new(workspace).upsert_field!(args)

        respond(
          form: form.slug, field: form_field.source_name,
          visible: form_field.visibility_mode == IncidentFormField::VISIBILITY_MODE_VISIBLE,
          required: form_field.required_mode != IncidentFormField::REQUIRED_MODE_OPTIONAL,
          locked: form_field.locked_required?,
          conditions: form_field.incident_conditions.count
        )
      end
    end
  end
end
