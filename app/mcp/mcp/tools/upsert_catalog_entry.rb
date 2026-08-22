module Mcp
  module Tools
    class UpsertCatalogEntry < Base
      tool_name UPSERT_CATALOG_ENTRY
      description "Create or update a service catalog entry. Pass slug to update an existing " \
                  "entry; omit it to create one (name required). Attributes must match the " \
                  "type's attribute definitions. If the call requires approval, retry the " \
                  "identical call with approval_id once approved. Docs: #{Docs::CATALOG}"
      annotations(**WRITE)
      input_schema(
        properties: {
          type: { type: "string", description: "Catalog type slug, e.g. service, team" },
          slug: { type: "string", description: "Existing entry slug to update; omit to create" },
          name: { type: "string", description: "Entry display name (required on create)" },
          attributes: {
            type: "object",
            description: "Attribute key/value pairs per the type's definitions, e.g. {\"description\": \"...\", \"owner_team\": \"platform\"}. " \
                         "An attribute referencing another entry takes that entry's slug or id. " \
                         "An attribute holding a person takes the email they sign in with, or their platform user id, " \
                         "and names someone who is already a workspace member"
          },
          approval_id: { type: "string", description: "Approval id when retrying an approved call" }
        },
        required: [ "type" ]
      )

      def self.authorization(workspace, args)
        [ ApiKey::RESOURCE_CATALOG, existing_entry(workspace, args) ? ApiKey::ACTION_UPDATE : ApiKey::ACTION_CREATE ]
      end

      def self.perform(workspace:, args:)
        type = workspace.catalog_types.find_by!(slug: args[:type].to_s)
        service = Catalogue::EntryService.new(workspace)
        raw_attributes = (args[:attributes] || {}).to_h

        entry =
          if (existing = existing_entry(workspace, args))
            service.update(existing, name: args[:name], raw_attributes: raw_attributes)
          else
            service.create(type: type, name: args[:name].to_s, raw_attributes: raw_attributes)
          end

        respond(slug: entry.slug, name: entry.name, type: type.slug, attributes: entry.attributes)
      end

      def self.existing_entry(workspace, args)
        return nil if args[:slug].blank?

        workspace.catalog_entries.active.find_by(slug: args[:slug].to_s)
      end
    end
  end
end
