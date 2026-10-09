module Mcp
  module Tools
    # What the map tools share. Each finds a resource the way a person names it, within what the caller reads, and answers
    # in the same rows and link lines, so a resource reads the same whichever tool found it.
    module MapPayloads
      CANDIDATES_SHOWN = 20
      NOT_A_CURSOR = "This cursor is not one a page gave.".freeze

      RESOURCE_PROPERTY = {
        type: "string",
        description: "A resource by its name, its provider's id or its id on the map, such as web, firefight-prod/main " \
                     "or an id find_resources gave. A name several resources share answers with each one's id"
      }.freeze

      # The resource named, or a response saying it is not on the map or listing those that share the name. A resource
      # outside what the caller reads answers exactly as a name nothing has.
      def locate(workspace, visible, reference)
        candidates = ResourceMap::Resource.candidates(visible, workspace, reference, removed: true)
        return refuse(error: ResourceMap::Resource.not_found_words(reference)) if candidates.empty?
        return candidates.first if candidates.one?

        more = candidates.size - CANDIDATES_SHOWN
        refuse({
          error: "More than one resource is called #{reference}. Name one by its id.",
          candidates: rows(candidates.first(CANDIDATES_SHOWN), visible),
          more: ("#{more} more share the name" if more.positive?)
        }.compact)
      end

      # How many links lead to resources in environments the caller cannot read, or nil when none do.
      def out_of_reach_words(count, within_two_hops: false)
        return nil unless count.positive?

        "#{count} more #{'link'.pluralize(count)}#{' within two hops' if within_two_hops} #{count == 1 ? 'leads' : 'lead'} " \
          "to resources in environments you cannot read"
      end

      # One row per resource, with how many resources directly depend on it, counted in one query and only among those
      # the caller reads.
      def rows(resources, visible)
        return [] if resources.empty?

        ActiveRecord::Associations::Preloader.new(records: resources, associations: { integration_environment: :environment }).call
        dependents = ResourceMap::Resource.where(id: resources.map(&:id))
                                          .pluck(:id, Arel.sql(ResourceMap::Query.dependents_sql("resource_map_resources.id", within: visible))).to_h
        resources.map { |resource| row(resource, dependents.fetch(resource.id, 0)) }
      end

      def row(resource, dependents)
        {
          id: resource.id, name: resource.name, kind: resource.kind, provider: resource.provider, account: resource.account,
          environment: resource.integration_environment&.environment&.name, status: resource.status, health: resource.health,
          dependents: dependents, gone_since: resource.removed_at&.iso8601
        }.compact
      end

      # The sentence a link reads as, with how it was found, as get_resource_map's fact sheet words it.
      def link_payload(link, from_side:)
        other = from_side ? link.to_resource : link.from_resource
        {
          sentence: link.sentence, relation: link.relation, origin: link.origin, how: GetResourceMap.how_found(link),
          confirmed: (link.confirmed_at.present? if link.suggested?), certainty: link.certainty, clues: link.clues.presence,
          settings: link.variables.presence,
          note: link.note.presence, other: { id: other.id, name: other.name, kind: other.kind, provider: other.provider,
                                             gone_since: other.removed_at&.iso8601 }.compact
        }.compact
      end

      # A cursor is the opaque id of the last row a page gave.
      def cursor_for(id) = Base64.urlsafe_encode64(id.to_s, padding: false)

      def after_cursor(cursor)
        return nil if cursor.blank?

        id = Base64.urlsafe_decode64(cursor.to_s)
        raise ResourceMap::Query::InvalidCursor, NOT_A_CURSOR unless id.match?(CatalogEntry::ReferenceManagement::UUID_FORMAT)

        id
      rescue ArgumentError
        raise ResourceMap::Query::InvalidCursor, NOT_A_CURSOR
      end

      def bad_cursor(error)
        Mcp::ToolDispatcher.error_response("#{error.message} Leave it out to start from the first page.")
      end

      def relations_property(about)
        { type: "array", items: { type: "string", enum: ResourceMap::RELATIONS }, description: about }
      end
    end
  end
end
