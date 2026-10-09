module Mcp
  module Tools
    # Finds resources on a map of any size by what they are, where they run and who owns them, a page at a time.
    class FindResources < Base
      extend MapPayloads

      tool_name FIND_RESOURCES
      authorize_as Ability::Action::RESOURCE_MAP
      description "Find resources on the resource map by what they are, where they run and who owns them, a page at a time. " \
                  "Filter by provider, kind, account, environment, status, health, owning team, catalog service, provider " \
                  "tag, exact details or the start of a name, or what changed since a time. Each row gives the resource's id, " \
                  "which every other map tool takes, its status as the last sweep saw it, and how many resources directly " \
                  "depend on it. Sort by name, or by dependents for what most else relies on. Only what runs in the " \
                  "environments the caller may read is found or counted. Docs: #{Docs::MCP_SERVER}"
      annotations(**READ_ONLY)
      choice :environment, from: ->(workspace) { workspace.environment_entries }
      choice :provider, from: MapFilters::PROVIDERS
      input_schema(
        properties: MapFilters::PROPERTIES.merge(
          sort: { type: "string", enum: ResourceMap::Query::SORTS, description: "name (the default) or dependents, most first" },
          limit: { type: "integer", description: "Rows per page. Default #{ResourceMap::Query::PAGE_SIZE}, most #{ResourceMap::Query::MAX_PAGE_SIZE}" },
          cursor: { type: "string", description: "next_cursor from the page before, with the same filters and sort" }
        )
      )

      def self.perform_with_principal(workspace:, principal:, args:)
        visible = ResourceMap::Resource.visible_to(principal, workspace)
        query = ResourceMap::Query.new(workspace, within: visible, sort: args[:sort].presence || ResourceMap::Query::SORT_NAME,
                                                  **MapFilters.from(workspace, args))
        page = query.page(cursor: args[:cursor], limit: args[:limit].presence || ResourceMap::Query::PAGE_SIZE)
        respond({ resources: rows(page.resources, visible), total: page.total_label, next_cursor: page.next_cursor }.compact)
      rescue MapFilters::Refused => refusal
        Mcp::ToolDispatcher.error_response(refusal.message)
      rescue ResourceMap::Query::InvalidCursor => error
        bad_cursor(error)
      end
    end
  end
end
