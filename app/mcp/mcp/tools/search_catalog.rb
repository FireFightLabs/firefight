module Mcp
  module Tools
    class SearchCatalog < Base
      tool_name SEARCH_CATALOG
      description "Search the service catalog: services, teams and other entries with their " \
                  "attributes and relationships (e.g. which team owns a service, its Slack " \
                  "channel). Use type=service or type=team plus a name query or exact slug."
      annotations(**READ_ONLY)
      input_schema(
        properties: {
          type: { type: "string", description: "Catalog type slug or system key, e.g. service, team" },
          query: { type: "string", description: "Matches entry names" },
          slug: { type: "string", description: "Exact entry slug" },
          limit: { type: "integer", description: "Max results, up to 50 (default 25)" }
        },
        required: []
      )

      def self.perform(workspace:, args:)
        scope = CatalogEntry.active.joins(:catalog_type)
          .where(workspace: workspace)
          .includes(:catalog_type, outgoing_relationships: { target_entry: :catalog_type })
          .order(:name)
        if args[:type].present?
          scope = scope.where(catalog_types: { slug: args[:type] })
            .or(scope.where(catalog_types: { system_key: args[:type] }))
        end
        scope = scope.where("catalog_entries.name ILIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(args[:query])}%") if args[:query].present?
        scope = scope.where(slug: args[:slug]) if args[:slug].present?

        entries, truncated = capped(scope, args)
        respond(entries: entries.map { |entry| summary(entry) }, truncated: truncated)
      end

      def self.summary(entry)
        {
          slug: entry.slug,
          name: entry.name,
          type: entry.catalog_type.system_key || entry.catalog_type.slug,
          attributes: entry.entry_attributes,
          relationships: entry.outgoing_relationships.map do |relationship|
            next if relationship.target_entry.deleted_at.present?

            {
              key: relationship.relationship_key,
              target_slug: relationship.target_entry.slug,
              target_name: relationship.target_entry.name,
              target_type: relationship.target_entry.catalog_type.system_key || relationship.target_entry.catalog_type.slug
            }
          end.compact
        }.compact
      end
    end
  end
end
