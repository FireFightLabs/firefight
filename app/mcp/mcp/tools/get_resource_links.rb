module Mcp
  module Tools
    # Every link into or out of one resource, a page at a time, each saying how it was found.
    class GetResourceLinks < Base
      extend MapPayloads

      DIRECTION_IN = "in".freeze
      DIRECTION_OUT = "out".freeze
      DIRECTION_BOTH = "both".freeze
      DIRECTIONS = [ DIRECTION_IN, DIRECTION_OUT, DIRECTION_BOTH ].freeze
      ORIGINS_FACTS = "facts".freeze
      ORIGINS_SUGGESTIONS = "suggestions".freeze
      ORIGINS_ALL = "all".freeze
      ORIGIN_CHOICES = [ ORIGINS_FACTS, ORIGINS_SUGGESTIONS, ORIGINS_ALL ].freeze
      PAGE_SIZE = 100
      MAX_PAGE_SIZE = 500

      tool_name GET_RESOURCE_LINKS
      authorize_as Ability::Action::RESOURCE_MAP
      description "The links into and out of one resource on the resource map, a page at a time. A link reads as a " \
                  "sentence, from depends on to, such as \"web uses orders-db\", with how it was found: declared by a " \
                  "provider, matched, added by a person, or a suggestion with its certainty and clues. A suggestion is " \
                  "not a fact until a person confirms it, so never state one as fact. Links to resources in environments " \
                  "the caller cannot read are left out and counted. Docs: #{Docs::MCP_SERVER}"
      annotations(**READ_ONLY)
      input_schema(
        properties: {
          resource: MapPayloads::RESOURCE_PROPERTY,
          direction: { type: "string", enum: DIRECTIONS, description: "out for what it depends on, in for what depends on it, both by default" },
          relations: relations_property("Only these relations. Every one by default"),
          origins: { type: "string", enum: ORIGIN_CHOICES, description: "facts (confirmed links only), suggestions (unconfirmed ones only) or all, the default" },
          limit: { type: "integer", description: "Links per page. Default #{PAGE_SIZE}, most #{MAX_PAGE_SIZE}" },
          cursor: { type: "string", description: "next_cursor from the page before, with the same arguments" }
        },
        required: [ "resource" ]
      )

      def self.perform_with_principal(workspace:, principal:, args:)
        visible = ResourceMap::Resource.visible_to(principal, workspace)
        resource = locate(workspace, visible, args[:resource])
        return resource if resource.is_a?(::MCP::Tool::Response)

        direction = args[:direction].presence || DIRECTION_BOTH
        links = chosen(links_of(resource, direction, visible.select(:id)), args[:relations], args[:origins])
        size = (args[:limit].presence || PAGE_SIZE).to_i.clamp(1, MAX_PAGE_SIZE)
        after = after_cursor(args[:cursor])
        page = (after ? links.where("resource_map_links.id > ?", after) : links).order(:id).limit(size + 1)
                 .includes(:from_resource, :to_resource, integration_environment: :integration).to_a
        shown = page.first(size)
        respond({
          resource: resource.name, total: links.count,
          links: shown.map { |link| link_payload(link, from_side: link.from_resource_id == resource.id) },
          next_cursor: (cursor_for(shown.last.id) if page.size > size),
          out_of_reach: out_of_reach(links_of(resource, direction, nil), visible)
        }.compact)
      rescue ResourceMap::Query::InvalidCursor => error
        bad_cursor(error)
      end

      # The standing links each way that the caller sees both ends of, or every one when inside is nil.
      def self.links_of(resource, direction, inside)
        out = ResourceMap::Link.standing.where(from_resource_id: resource.id)
        into = ResourceMap::Link.standing.where(to_resource_id: resource.id)
        out = out.where(to_resource_id: inside) if inside
        into = into.where(from_resource_id: inside) if inside
        case direction
        when DIRECTION_OUT then out
        when DIRECTION_IN then into
        else out.or(into)
        end
      end

      def self.chosen(links, relations, origins)
        links = links.where(relation: Array(relations)) if relations.present?
        case origins
        when ORIGINS_FACTS then links.facts
        when ORIGINS_SUGGESTIONS then links.to_review
        else links
        end
      end

      def self.out_of_reach(every, visible)
        hidden = every.count - every.where(from_resource_id: visible.select(:id), to_resource_id: visible.select(:id)).count
        "#{hidden} more #{'link'.pluralize(hidden)} #{hidden == 1 ? 'leads' : 'lead'} to resources in environments you cannot read" if hidden.positive?
      end
    end
  end
end
