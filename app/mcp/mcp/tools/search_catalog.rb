module Mcp
  module Tools
    class SearchCatalog < Base
      tool_name SEARCH_CATALOG
      authorize_as ApiKey::RESOURCE_CATALOG
      description "Search the service catalog: services, teams and other entries with their " \
                  "attributes and relationships (e.g. which team owns a service, its Slack " \
                  "channel). Use type=service or type=team plus a name query or exact slug. " \
                  "Docs: #{Docs::CATALOG}"
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
          .includes({ catalog_type: :catalog_attribute_definitions },
                    outgoing_relationships: [ :catalog_attribute_definition, { target_entry: :catalog_type } ])
          .order(:name)
        if args[:type].present?
          scope = scope.where(catalog_types: { slug: args[:type] })
            .or(scope.where(catalog_types: { system_key: args[:type] }))
        end
        scope = scope.search(args[:query]) if args[:query].present?
        scope = scope.where(slug: args[:slug]) if args[:slug].present?

        entries, truncated = capped(scope, args)
        member_names = member_names_for(workspace, entries)
        respond(entries: entries.map { |entry| summary(entry, member_names) }, truncated: truncated)
      end

      def self.summary(entry, member_names)
        {
          slug: entry.slug,
          name: entry.name,
          type: entry.catalog_type.system_key || entry.catalog_type.slug,
          attributes: attributes_with_member_names(entry, member_names),
          relationships: entry.active_outgoing_relationships.map do |relationship|
            {
              key: relationship.attribute_slug,
              target_slug: relationship.target_entry.slug,
              target_name: relationship.target_entry.name,
              target_type: relationship.target_entry.catalog_type.system_key || relationship.target_entry.catalog_type.slug
            }
          end
        }.compact
      end

      # Membership UUIDs are opaque to MCP clients. Resolve display names in
      # one query and emit { id, name } pairs in their place.
      def self.member_names_for(workspace, entries)
        ids = entries.flat_map do |entry|
          entry.catalog_type.member_attribute_slugs.flat_map { |key| Array(entry.entry_attributes[key]) }
        end.compact.uniq
        return {} if ids.empty?

        workspace.workspace_memberships.where(id: ids).includes(:user)
          .index_by(&:id).transform_values(&:display_name)
      end

      def self.attributes_with_member_names(entry, member_names)
        attributes = entry.entry_attributes
        entry.catalog_type.member_attribute_slugs.each do |key|
          next unless attributes.key?(key)

          attributes = attributes.merge(
            key => resolve_member_value(attributes[key], member_names)
          )
        end
        attributes
      end

      def self.resolve_member_value(value, member_names)
        if value.is_a?(Array)
          value.map { |id| { id: id, name: member_names[id] }.compact }
        elsif value.present?
          { id: value, name: member_names[value] }.compact
        end
      end
    end
  end
end
