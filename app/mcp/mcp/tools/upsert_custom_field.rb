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

      upserts ApiKey::RESOURCE_CUSTOM_FIELDS, scope: ->(workspace) { workspace.incident_field_definitions.active }

      def self.perform(workspace:, args:)
        existing = upsert_target(workspace, args)
        service = IncidentFieldDefinitionService.new(workspace)
        attrs = definition_attributes(workspace, args, existing)

        definition = existing ? service.update(existing, attrs) : service.create(attrs)

        respond(
          slug: definition.slug, name: definition.name, field_type: definition.field_type,
          option_source: definition.option_source,
          options: definition.incident_field_options.active.map { |o| { id: o.id, label: o.label } }
        )
      end

      def self.definition_attributes(workspace, args, existing)
        {
          name: args[:name].presence || existing&.name,
          description: args.key?(:description) ? args[:description] : existing&.description,
          field_type: args[:field_type].presence || existing&.field_type,
          option_source: args[:option_source].presence || existing&.option_source,
          catalog_type_id: catalog_type_id(workspace, args, existing),
          options: option_params(args, existing)
        }
      end

      def self.catalog_type_id(workspace, args, existing)
        return existing&.catalog_type_id unless args.key?(:catalog_type)
        return nil if args[:catalog_type].blank?

        workspace.catalog_types.active.find_by!(slug: args[:catalog_type].to_s).id
      end

      # Labels are the only handle an agent has, so an incoming label that
      # already exists reuses that option's row rather than replacing it. That
      # is what keeps a rename from orphaning the incidents pointing at it.
      def self.option_params(args, existing)
        return existing_option_params(existing) unless args.key?(:options)

        by_label = existing&.incident_field_options&.index_by(&:label) || {}

        Array(args[:options]).filter_map do |label|
          label = label.to_s.strip
          next if label.blank?

          { id: by_label[label]&.id, label: label }
        end
      end

      def self.existing_option_params(existing)
        return [] unless existing

        existing.incident_field_options.map do |option|
          { id: option.id, label: option.label, disabled: !option.enabled? }
        end
      end
    end
  end
end
