module Mcp
  module Tools
    # One resource's fact sheet, as get_resource_map gives it, with its links counted rather than walked, for a reader
    # that walks the map with the tools made for it.
    class GetResource < Base
      extend MapPayloads

      tool_name GET_RESOURCE
      authorize_as Ability::Action::RESOURCE_MAP
      description "One resource on the resource map by its name, its provider's id or its id: where it runs, its page, " \
                  "status as the last sweep saw it, details, the catalog services it runs with what each is for and who " \
                  "owns it, what people confirmed about it, how its recent incidents ended and what normal looks like for " \
                  "its metrics, its key checks with their normal (run_key_query runs one), with how many links lead in and " \
                  "out of it by relation. get_resource_links lists the links, " \
                  "get_resource_neighbours the resources one link away. Docs: #{Docs::MCP_SERVER}"
      annotations(**READ_ONLY)
      input_schema(properties: { resource: MapPayloads::RESOURCE_PROPERTY }, required: [ "resource" ])

      def self.perform_with_principal(workspace:, principal:, args:)
        visible = ResourceMap::Resource.visible_to(principal, workspace)
        resource = locate(workspace, visible, args[:resource])
        return resource if resource.is_a?(::MCP::Tool::Response)

        sheet = GetResourceMap.sheet(resource, visible, principal: principal, links: false)
        respond(sheet.merge(id: resource.id, provider_id: resource.external_id, health: resource.health, **link_counts(resource, visible)))
      end

      # Facts by relation each way, with unconfirmed suggestions and links leading out of the caller's reach counted apart.
      def self.link_counts(resource, visible)
        inside = visible.select(:id)
        out = ResourceMap::Link.standing.where(from_resource_id: resource.id)
        into = ResourceMap::Link.standing.where(to_resource_id: resource.id)
        seen_out = out.where(to_resource_id: inside)
        seen_in = into.where(from_resource_id: inside)
        suggested = { out: seen_out.to_review.count, in: seen_in.to_review.count }.select { |_, count| count.positive? }
        hidden = out.where.not(to_resource_id: inside).count + into.where.not(from_resource_id: inside).count
        {
          links_out: seen_out.facts.group(:relation).count, links_in: seen_in.facts.group(:relation).count,
          unconfirmed_suggestions: suggested.presence,
          out_of_reach: (hidden.positive? ? "#{hidden} more #{'link'.pluralize(hidden)} #{hidden == 1 ? 'leads' : 'lead'} to resources in environments you cannot read" : nil)
        }.compact
      end
    end
  end
end
