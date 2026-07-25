module Mcp
  module Tools
    class DeleteCatalogEntry < Base
      tool_name DELETE_CATALOG_ENTRY
      description "Soft-delete a service catalog entry by slug. If the call requires approval, " \
                  "retry the identical call with approval_id once approved. Docs: #{Docs::CATALOG}"
      annotations(**DESTRUCTIVE)
      authorize_as ApiKey::RESOURCE_CATALOG, ApiKey::ACTION_DELETE
      input_schema(
        properties: {
          slug: { type: "string", description: "Entry slug" },
          approval_id: { type: "string", description: "Approval id when retrying an approved call" }
        },
        required: [ "slug" ]
      )

      def self.perform(workspace:, args:)
        entry = workspace.catalog_entries.active.find_by!(slug: args[:slug].to_s)
        Catalogue::EntryService.new(workspace).delete(entry)

        respond(slug: entry.slug, deleted: true)
      end
    end
  end
end
