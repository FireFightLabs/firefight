module Mcp
  module Tools
    # What fails with a resource, which is everything with a path of fact links into it, summed up, with what suggestions
    # would add kept apart.
    class BlastRadius < Base
      extend MapPayloads

      MAX_HOPS = 10
      TOP_SHOWN = 25

      tool_name BLAST_RADIUS
      authorize_as Ability::Action::RESOURCE_MAP
      description "What fails with a resource on the resource map: every resource with a path of confirmed links into " \
                  "it, up to #{MAX_HOPS} links away, counted by kind, provider and environment, the catalog services they " \
                  "run with who owns each, the open incidents on those services, and the #{TOP_SHOWN} dependents most else " \
                  "relies on. What unconfirmed suggestions would add is counted apart and never in the total, and listed " \
                  "when suggestions are asked for. Only resources in environments the caller may read are walked or " \
                  "counted. Docs: #{Docs::MCP_SERVER}"
      annotations(**READ_ONLY)
      input_schema(
        properties: {
          resource: MapPayloads::RESOURCE_PROPERTY,
          hops: { type: "integer", description: "How many links to follow, 1 to #{MAX_HOPS}. Default #{MAX_HOPS}" },
          include_suggestions: { type: "boolean", description: "List the resources unconfirmed suggestions would add. They are always counted" }
        },
        required: [ "resource" ]
      )

      def self.perform_with_principal(workspace:, principal:, args:)
        visible = ResourceMap::Resource.visible_to(principal, workspace)
        resource = locate(workspace, visible, args[:resource])
        return resource if resource.is_a?(::MCP::Tool::Response)

        radius = ResourceMap::BlastRadius.new(resource, within: visible, hops: (args[:hops].presence || MAX_HOPS).to_i.clamp(1, MAX_HOPS))
        services = radius.services
        respond({
          resource: resource.name, hops: radius.graph.hops, dependents: radius.total,
          by_kind: radius.by_kind, by_provider: radius.by_provider,
          by_environment: radius.by_environment.transform_keys { |name| name || GetResourceMap::NO_ENVIRONMENT },
          services: services.map { |service| service_line(service) },
          open_incidents: services.flat_map(&:open_incidents).uniq.sort_by(&:identifier).map { |incident| "#{incident.identifier} #{incident.name}" },
          top_dependents: rows(radius.top_dependents(limit: TOP_SHOWN), visible),
          suggestions_would_add: suggested(radius, visible, args[:include_suggestions] == true)
        }.compact)
      end

      def self.service_line(service)
        owners = service.owning_teams.map(&:name)
        incidents = service.open_incidents.map(&:identifier)
        "#{service.entry.name} (#{service.entry.catalog_type.name})#{", owned by #{owners.to_sentence}" if owners.any?}" \
          "#{", open incidents #{incidents.to_sentence}" if incidents.any?}"
      end

      def self.suggested(radius, visible, listed)
        ids = radius.suggested_dependent_ids
        return nil if ids.empty?

        found = { count: ids.size, note: "Unconfirmed suggestions, not counted in dependents" }
        return found.merge(note: "#{found[:note]}. Ask with include_suggestions to list them") unless listed

        resources = ResourceMap::Resource.where(id: ids).order(Arel.sql(ResourceMap::Query::NAME_ORDER), :id).limit(TOP_SHOWN).to_a
        found.merge(resources: rows(resources, visible), more: (ids.size > TOP_SHOWN ? "#{ids.size - TOP_SHOWN} more" : nil)).compact
      end
    end
  end
end
