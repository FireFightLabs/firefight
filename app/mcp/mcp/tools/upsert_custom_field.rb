module Mcp
  module Tools
    class UpsertCustomField < Base
      tool_name UPSERT_CUSTOM_FIELD
      description "Create or update a custom incident field definition. Pass slug to update an " \
                  "existing field; omit it to create one (name and field_type required). " \
                  "Options are matched by label, so renaming one keeps every incident pointing " \
                  "at it. A field's type and option source lock once incidents hold values. " \
                  "If the call requires approval, retry the identical call with approval_id " \
                  "once approved. Docs: #{Docs::CUSTOM_FIELDS}"
      annotations(**WRITE)
      input_schema(
        properties: {
          slug: { type: "string", description: "Existing field slug to update; omit to create. An unknown slug is an error, not a create" },
          name: { type: "string", description: "Field display name (required on create)" },
          description: { type: "string", description: "Help text responders see under the field" },
          field_type: {
            type: "string",
            description: "One of: #{IncidentFieldDefinition::FIELD_TYPES.join(', ')}"
          },
          option_source: {
            type: "string",
            description: "One of: #{IncidentFieldDefinition::OPTION_SOURCES.join(', ')}. " \
                         "fixed means the options listed here, catalog means a catalog type"
          },
          catalog_type: { type: "string", description: "Catalog type slug, required when option_source is catalog" },
          options: {
            type: "array",
            description: "Option labels in display order for a fixed list, e.g. [\"Payments\", \"Checkout\"]. " \
                         "Replaces the current set: a label already present keeps its identity, one left out " \
                         "is removed when nothing references it",
            items: { type: "string" }
          },
          approval_id: { type: "string", description: "Approval id when retrying an approved call" }
        },
        required: []
      )

      upserts Ability::Action::RESOURCE_CUSTOM_FIELDS, scope: ->(workspace) { workspace.incident_field_definitions.active }

      def self.perform(workspace:, args:)
        definition = IncidentFieldDefinitionService.new(workspace)
          .upsert!(upsert_target(workspace, args), args)

        respond(
          slug: definition.slug, name: definition.name, field_type: definition.field_type,
          option_source: definition.option_source,
          options: definition.incident_field_options.active.map { |o| { id: o.id, label: o.label } }
        )
      end
    end
  end
end
