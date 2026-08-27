module Mcp
  module Tools
    class DeleteCatalogType < Base
      tool_name DELETE_CATALOG_TYPE
      authorize_as Ability::Action::RESOURCE_CATALOG, Ability::Action::ACTION_DELETE
      description "Remove a kind of thing from the catalog, along with the entries under it. " \
                  "Built-in types cannot be removed, and neither can one that another type's " \
                  "reference attribute points at, since its entries would vanish from that " \
                  "picker. The refusal names what is in the way. If the call requires approval, " \
                  "retry the identical call with approval_id once approved. Docs: #{Docs::CATALOG}"
      annotations(**DESTRUCTIVE)
      input_schema(
        properties: {
          slug: { type: "string", description: "Slug of the type to remove" },
          approval_id: { type: "string", description: "Approval id when retrying an approved call" }
        },
        required: [ "slug" ]
      )

      def self.perform(workspace:, args:)
        type = UpsertCatalogType.find_type!(workspace, args[:slug])
        blocked_reason = type.deletion_blocked_reason
        return Mcp::ToolDispatcher.error_response(blocked_reason) if blocked_reason

        entries = type.catalog_entries.active.count
        type.soft_delete!

        respond(slug: type.slug, deleted: true, entries_removed: entries)
      end
    end
  end
end
