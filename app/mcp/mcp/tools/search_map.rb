module Mcp
  module Tools
    # One search across resources on the map, catalog entries and their owners, and memories people confirmed, ranked
    # together, so a name, an id, a fragment of one or what a service does finds it wherever it lives.
    class SearchMap < Base
      tool_name SEARCH_MAP
      authorize_as Ability::Action::RESOURCE_MAP
      description "Search the resource map, the catalog and confirmed memories at once, by a name, a provider id or " \
                  "part of one, a tag, an owning team, or what a service does. Results are ranked together, an exact " \
                  "name or id first, and each says what it is, why it matched and where to open it. Use it to find " \
                  "something when you do not know its exact name or where it runs, then read it with the map tools. " \
                  "Only what the caller may read is searched: resources in the environments it reads, the catalog with " \
                  "catalog read, memories with memory read. Docs: #{Docs::MCP_SERVER}"
      annotations(**READ_ONLY)
      input_schema(
        properties: {
          query: { type: "string", description: "What to find, such as payments-db, checkout, team=ledger or the service that sends receipts" },
          types: { type: "array", items: { type: "string", enum: SearchDocument::Search::TYPES },
                   description: "What to search: resource, catalog_entry, memory. All three by default, or resources alone when a map filter is given" }
        }.merge(MapFilters::PROPERTIES).merge(
          limit: { type: "integer", description: "Results per page. Default #{SearchDocument::Search::DEFAULT_LIMIT}, most #{SearchDocument::Search::MAX_LIMIT}" },
          cursor: { type: "string", description: "next_cursor from the page before, with the same query, types and filters" }
        ),
        required: [ "query" ]
      )

      def self.perform_with_principal(workspace:, principal:, args:)
        query = args[:query].to_s.squish
        return Mcp::ToolDispatcher.error_response("Say what to find first.") if query.blank?

        page = MapSearchService.new(workspace, principal).search(
          query, types: args[:types], filters: MapFilters.from(workspace, args).compact_blank, limit: args[:limit], cursor: args[:cursor]
        )
        respond({
          results: page.results.map { |result| payload(result) }, next_cursor: page.next_cursor,
          not_searched: (page.left_out.map { |type| "#{type}: not readable with this connection's permissions" } if page.left_out.any?)
        }.compact)
      rescue MapFilters::Refused, SearchDocument::Search::InvalidCursor => refusal
        Mcp::ToolDispatcher.error_response(refusal.message)
      end

      def self.payload(result)
        { type: result.type, id: result.id, title: result.title, why: result.why }.merge(facts(result)).merge(link: result.url)
      end

      def self.facts(result)
        record = result.record
        case result.type
        when SearchDocument::Search::TYPE_RESOURCE
          { kind: record.kind, provider: record.provider, account: record.account, environment: record.integration_environment&.environment&.name,
            status: record.status }.compact
        when SearchDocument::Search::TYPE_CATALOG_ENTRY
          { catalog_type: record.catalog_type.name, slug: record.slug, description: record.purpose }.compact
        when SearchDocument::Search::TYPE_MEMORY
          { about: record.about, trust: record.trust }.compact
        end
      end
    end
  end
end
