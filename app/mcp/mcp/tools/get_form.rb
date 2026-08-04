module Mcp
  module Tools
    class GetForm < Base
      tool_name GET_FORM
      description "Fetch one lifecycle form and every field on it, hidden ones included, with " \
                  "each field's key, type, whether it is visible, required, locked, and any " \
                  "conditions gating it. Read this before changing a form so an update replaces " \
                  "what is actually there. Docs: #{Docs::INCIDENT_FORMS}"
      annotations(**READ_ONLY)
      input_schema(
        properties: {
          form: { type: "string", description: "Form slug, one of: #{IncidentForm::SLUGS.join(', ')}" }
        },
        required: [ "form" ]
      )

      def self.authorization(_workspace, _args)
        [ ApiKey::RESOURCE_FORMS, ApiKey::ACTION_READ ]
      end

      def self.perform(workspace:, args:)
        slug = args[:form].to_s
        unless IncidentForm::SLUGS.include?(slug)
          raise ArgumentError, "unknown form #{slug.inspect}. Valid: #{IncidentForm::SLUGS.join(', ')}"
        end

        form = workspace.incident_forms.find_by(slug: slug) ||
          IncidentForm.new(workspace: workspace, **IncidentForm::DEFAULTS_BY_SLUG.fetch(slug))

        respond(form: slug, name: form.name, fields: form.resolved_fields(include_hidden: true).map { |f| field_payload(f) })
      end

      def self.field_payload(form_field)
        {
          name: form_field.source_name,
          slug: form_field.system_field_key || form_field.incident_field_definition&.slug,
          source: form_field.field_source_kind,
          visible: form_field.visibility_mode == IncidentFormField::VISIBILITY_MODE_VISIBLE,
          required: form_field.required_mode != IncidentFormField::REQUIRED_MODE_OPTIONAL,
          locked: form_field.locked_required?,
          conditions: form_field.incident_conditions.map do |condition|
            { condition_field: condition.condition_field, operator: condition.operator, values: condition.values }
          end
        }
      end
    end
  end
end
