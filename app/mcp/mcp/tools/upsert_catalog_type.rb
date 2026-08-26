module Mcp
  module Tools
    class UpsertCatalogType < Base
      tool_name UPSERT_CATALOG_TYPE
      authorize_as Ability::Action::RESOURCE_CATALOG, Ability::Action::ACTION_UPDATE
      description "Create a kind of thing the catalog holds, such as Service or Datastore, or " \
                  "change the attributes entries under it carry. Pass slug to change the one that " \
                  "has it, leave it out to create a new one. Attributes are matched by name, so " \
                  "resending a list renames rather than replaces and the entries already holding " \
                  "a value keep it, and leaving one out removes it, which is refused while an " \
                  "entry still uses it. Sending no attributes at all leaves the shape alone. " \
                  "A reference attribute names the type it points at by slug. Built-in types " \
                  "keep their slug and their own fields. If the call requires approval, retry " \
                  "the identical call with approval_id once approved. Docs: #{Docs::CATALOG}"
      annotations(**WRITE)
      input_schema(
        properties: {
          slug: { type: "string", description: "Slug of the type to change. Leave out to create one" },
          name: { type: "string", description: "What this kind of thing is called, e.g. Datastore" },
          description: { type: "string", description: "What belongs under this type" },
          attributes: {
            type: "array",
            description: "What every entry of this type carries, e.g. " \
                         "[{\"name\": \"Owning team\", \"attribute_type\": \"reference\", \"reference_type\": \"team\"}]. " \
                         "attribute_type is one of #{CatalogAttributeDefinition::ATTRIBUTE_TYPES.join(', ')}. " \
                         "A select takes options, a reference takes reference_type. role tags an " \
                         "attribute for alert routing and is one of #{CatalogAttributeDefinition::ROLES.join(', ')}",
            items: { type: "object" }
          },
          approval_id: { type: "string", description: "Approval id when retrying an approved call" }
        },
        required: []
      )

      def self.perform(workspace:, args:)
        existing = args[:slug].present? ? find_type!(workspace, args[:slug]) : nil
        raise ArgumentError, "pass name when creating a type" if existing.nil? && args[:name].blank?

        type = CatalogType::Upsert.new(workspace).call(existing, args)

        respond(
          slug: type.slug, name: type.name, kind: type.kind,
          attributes: type.catalog_attribute_definitions.sort_by(&:position).map { |definition| summary(definition) },
          entries: type.catalog_entries.active.count
        )
      end

      def self.find_type!(workspace, slug)
        workspace.catalog_types.active.find_by(slug: slug.to_s) ||
          raise(ArgumentError, "unknown catalog type #{slug.to_s.inspect}")
      end

      def self.summary(definition)
        {
          slug: definition.slug, name: definition.name, attribute_type: definition.attribute_type,
          required: definition.required, role: definition.role,
          reference_type: definition.reference? ? definition.reference_type&.slug : nil
        }.compact
      end
    end
  end
end
