module Mcp
  module Tools
    # A walk along the map's links from one resource, towards what it depends on or what depends on it.
    class TraverseResourceMap < Base
      extend MapPayloads

      MAX_HOPS = 6
      DEFAULT_HOPS = 2
      LIMIT = ResourceMap::Graph::NODE_LIMIT

      tool_name TRAVERSE_RESOURCE_MAP
      authorize_as Ability::Action::RESOURCE_MAP
      description "Walk the resource map's links from one resource, towards what it depends on (depends_on) or what " \
                  "depends on it (dependents), up to #{MAX_HOPS} links away. Each resource reached is a row with the " \
                  "fewest links between it and the start (hop) and the link it was reached by (via). Runtime links only " \
                  "unless relations are named, so a repository a resource is managed in is left out, and facts only " \
                  "unless suggestions are asked for. At most #{LIMIT} resources, nearest first, " \
                  "and it says how many more it reached. blast_radius sums up what fails with a resource. Docs: #{Docs::MCP_SERVER}"
      annotations(**READ_ONLY)
      input_schema(
        properties: {
          resource: MapPayloads::RESOURCE_PROPERTY,
          direction: { type: "string", enum: ResourceMap::Graph::DIRECTIONS, description: "depends_on or dependents" },
          hops: { type: "integer", description: "How many links to follow, 1 to #{MAX_HOPS}. Default #{DEFAULT_HOPS}" },
          relations: relations_property("Only follow these relations. The runtime ones by default, every relation but managed_by"),
          kinds: { type: "array", items: { type: "string", enum: ResourceMap::KINDS },
                   description: "Only list resources of these kinds. The walk still goes through others" },
          include_suggestions: { type: "boolean", description: "Also follow links suggested and not yet confirmed. Off by default" }
        },
        required: [ "resource", "direction" ]
      )

      def self.perform_with_principal(workspace:, principal:, args:)
        visible = ResourceMap::Resource.visible_to(principal, workspace)
        resource = locate(workspace, visible, args[:resource])
        return resource if resource.is_a?(::MCP::Tool::Response)

        graph = ResourceMap::Graph.new(resource, direction: args[:direction].to_s, relations: args[:relations], kinds: args[:kinds],
                                                 suggestions: args[:include_suggestions] == true, within: visible, limit: LIMIT,
                                                 hops: (args[:hops].presence || DEFAULT_HOPS).to_i.clamp(1, MAX_HOPS))
        nodes = graph.nodes
        rows = rows(nodes.map(&:resource), visible).index_by { |row| row[:id] }
        vias = vias(graph, resource, nodes)
        respond({
          resource: resource.name, direction: graph.direction, hops: graph.hops, reached: graph.total,
          resources: nodes.map { |node| rows.fetch(node.resource.id).merge({ hop: node.hop, via: vias[node.resource.id] }.compact) },
          left_out: (left_out(graph.truncated) if graph.truncated.positive?)
        }.compact)
      end

      def self.left_out(count)
        "#{count} more #{'resource'.pluralize(count)} #{count == 1 ? 'was' : 'were'} reached and not listed, narrow the walk by kinds or hops"
      end

      # The link each resource was reached by from one a hop nearer, the first by name when several were. A resource
      # reached only through kinds left out of the list has none shown.
      def self.vias(graph, root, nodes)
        hops = nodes.to_h { |node| [ node.resource.id, node.hop ] }.merge(root.id => 0)
        dependents = graph.direction == ResourceMap::Graph::DEPENDENTS
        graph.links.to_a.sort_by(&:sentence).each_with_object({}) do |link, vias|
          reached, from = dependents ? [ link.from_resource_id, link.to_resource_id ] : [ link.to_resource_id, link.from_resource_id ]
          next unless hops[reached] && hops[from] && hops[from] == hops[reached] - 1

          vias[reached] ||= link.sentence
        end
      end
    end
  end
end
