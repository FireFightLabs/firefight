module Mcp
  module Tools
    # The resources one link from a resource, each way, grouped by how they are linked.
    class GetResourceNeighbours < Base
      extend MapPayloads

      LIMIT = 200

      tool_name GET_RESOURCE_NEIGHBOURS
      authorize_as Ability::Action::RESOURCE_MAP
      description "The resources one link away from a resource on the resource map, both ways: what it depends on and " \
                  "what depends on it, grouped by relation, each as a row with its id, status and how many depend on it. " \
                  "Facts only unless suggestions are asked for, and the answer says how many suggestions it left out. " \
                  "At most #{LIMIT}, and it says how many more there are. traverse_resource_map goes further than one " \
                  "link. Docs: #{Docs::MCP_SERVER}"
      annotations(**READ_ONLY)
      input_schema(
        properties: {
          resource: MapPayloads::RESOURCE_PROPERTY,
          include_suggestions: { type: "boolean", description: "Also links suggested and not yet confirmed by a person, marked as such. Off by default" }
        },
        required: [ "resource" ]
      )

      def self.perform_with_principal(workspace:, principal:, args:)
        visible = ResourceMap::Resource.visible_to(principal, workspace)
        resource = locate(workspace, visible, args[:resource])
        return resource if resource.is_a?(::MCP::Tool::Response)

        suggestions = args[:include_suggestions] == true
        inside = visible.select(:id)
        every = ResourceMap::Link.standing.where(from_resource_id: resource.id, to_resource_id: inside)
                                 .or(ResourceMap::Link.standing.where(to_resource_id: resource.id, from_resource_id: inside))
        links = suggestions ? every : every.facts
        found = links.includes(:from_resource, :to_resource).order(:relation, :id).limit(LIMIT + 1).to_a
        shown = found.first(LIMIT)
        rows = rows(shown.map { |link| other_end(link, resource) }.uniq, visible).index_by { |row| row[:id] }
        left_out = suggestions ? 0 : every.to_review.count
        respond({
          resource: resource.name,
          depends_on: grouped(shown.select { |link| link.from_resource_id == resource.id }, resource, rows),
          dependents: grouped(shown.select { |link| link.to_resource_id == resource.id }, resource, rows),
          more: (more(links.count - LIMIT, resource) if found.size > LIMIT),
          suggestions_left_out: (left_out.positive? ? "#{left_out} unconfirmed #{'suggestion'.pluralize(left_out)} left out, ask with include_suggestions to see them" : nil)
        }.compact)
      end

      def self.more(count, resource)
        "#{count} more #{'link'.pluralize(count)} #{count == 1 ? 'leads' : 'lead'} to or from #{resource.name}, get_resource_links pages through them"
      end

      def self.other_end(link, resource) = link.from_resource_id == resource.id ? link.to_resource : link.from_resource

      # By relation, each neighbour once per relation, a suggestion marked as not confirmed.
      def self.grouped(links, resource, rows)
        links.group_by(&:relation).transform_values do |related|
          related.map do |link|
            rows.fetch(other_end(link, resource).id).merge({ unconfirmed: (true if link.unconfirmed?) }.compact)
          end
        end
      end
    end
  end
end
