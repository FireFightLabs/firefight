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
        form = workspace.ensure_incident_form!(form_slug(args))
        service = IncidentFormService.new(workspace)
        form_field = resolve_field(form, service, args)

        service.update_field(
          form_field,
          visibility_mode: visibility_mode(args, form_field),
          required_mode: required_mode(args, form_field)
        )
        form_field.sync_conditions!(condition_params(workspace, args)) if args.key?(:conditions)

        form_field.reload
        respond(
          form: form.slug, field: form_field.source_name,
          visible: form_field.visibility_mode == IncidentFormField::VISIBILITY_MODE_VISIBLE,
          required: form_field.required_mode != IncidentFormField::REQUIRED_MODE_OPTIONAL,
          locked: form_field.locked_required?,
          conditions: form_field.incident_conditions.count
        )
      end

      def self.form_slug(args)
        slug = args[:form].to_s
        raise ArgumentError, "unknown form #{slug.inspect}. Valid: #{IncidentForm::SLUGS.join(', ')}" unless IncidentForm::SLUGS.include?(slug)

        slug
      end

      # A system field has no row until something about it is changed, and a
      # custom field has none until it is attached, so both are materialized
      # here rather than making the agent create one first.
      def self.resolve_field(form, service, args)
        if args[:system_field].present?
          service.ensure_system_field!(form, args[:system_field].to_s)
        elsif args[:custom_field].present?
          definition = form.workspace.incident_field_definitions.active.find_by(slug: args[:custom_field].to_s)
          raise ArgumentError, "unknown custom field #{args[:custom_field].to_s.inspect}" if definition.nil?

          existing = form.incident_form_fields.find_by(incident_field_definition_id: definition.id)
          existing || service.add_custom_field(form, definition)
        else
          raise ArgumentError, "pass either custom_field or system_field"
        end
      end

      def self.visibility_mode(args, form_field)
        return form_field.visibility_mode unless args.key?(:visible)

        args[:visible] ? IncidentFormField::VISIBILITY_MODE_VISIBLE : IncidentFormField::VISIBILITY_MODE_HIDDEN
      end

      def self.required_mode(args, form_field)
        return form_field.required_mode unless args.key?(:required)

        args[:required] ? IncidentFormField::REQUIRED_MODE_REQUIRED : IncidentFormField::REQUIRED_MODE_OPTIONAL
      end

      def self.condition_params(workspace, args)
        Array(args[:conditions]).map do |condition|
          ConditionValues.attributes(workspace, condition.to_h.with_indifferent_access)
        end
      end
    end
  end
end
