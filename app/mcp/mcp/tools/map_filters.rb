module Mcp
  module Tools
    # The filters find_resources and resource_map_stats share, turned into ResourceMap::Query's. A team or catalog entry
    # is named the way a person would, and one the catalog does not hold is refused rather than read as no filter.
    module MapFilters
      Refused = Class.new(StandardError)

      def self.list(about) = { type: "array", items: { type: "string" }, description: about }

      # The provider filter lists what is on this workspace's map, so no provider is named in shared text.
      PROVIDERS = ->(workspace) { ResourceMap.providers(workspace) }

      PROPERTIES = {
        provider: list("Providers by key"),
        kind: { type: "array", items: { type: "string", enum: ResourceMap::KINDS }, description: "Kinds of resource" },
        account: list("Accounts as the map names them, as find_resources rows show them"),
        environment: list("Environments by slug or name, the environment the connection that reported a resource is wired to"),
        status: list("Statuses as the last sweep saw them, such as running or failed"),
        health: { type: "array", items: { type: "string", enum: ResourceMap::Resource::HEALTHS },
                  description: "How the status reads: ok, busy, failing, or unknown for a status Firefight does not know" },
        owner: { type: "string", description: "A team in the catalog by name or id: what it owns, linked to the team or to a service it owns" },
        catalog_entry: { type: "string", description: "A catalog entry, such as a service, by name, slug or id: the resources it runs on" },
        tag: list("Provider tags, each key=value or a key alone for any value, such as team=payments"),
        field: { type: "object", description: "Details that must match exactly, such as {\"engine\": \"postgres 16\"}" },
        name_starts_with: { type: "string", description: "The start of a name, any case" },
        changed_since: { type: "string", description: "ISO 8601 time: only resources a sweep saw change since then" },
        include_removed: { type: "boolean", description: "Also resources their connection no longer reports. Left out by default" }
      }.freeze

      def self.from(workspace, args)
        {
          provider: args[:provider], kind: args[:kind], account: args[:account], environment: environments(workspace, args[:environment]),
          status: args[:status], health: args[:health], owner: (team(workspace, args[:owner]) if args[:owner].present?),
          catalog_entry: (entry(workspace, args[:catalog_entry]) if args[:catalog_entry].present?), tag: args[:tag],
          fields: args[:field].presence&.to_h, name_prefix: args[:name_starts_with], changed_since: time(args[:changed_since]),
          include_removed: args[:include_removed] == true
        }
      end

      # Each by its catalog entry's name, which is what the query matches.
      def self.environments(workspace, references)
        Array(references).presence&.map { |reference| one(workspace.environment_entries, reference, "environment").name }
      end

      def self.team(workspace, reference) = one(workspace.catalog_entries.in_system_type(CatalogType::SYSTEM_KEY_TEAM), reference, "team")

      def self.entry(workspace, reference) = one(workspace.catalog_entries.active, reference, "catalog entry")

      def self.one(entries, reference, noun)
        found = entries.referenced(reference).to_a
        wanted = reference.to_s.strip
        raise Refused, "No #{noun} called #{wanted} is in the catalog." if found.empty?
        raise Refused, "More than one #{noun} is called #{wanted}: #{found.map { |each| "#{each.name} (#{each.id})" }.join(', ')}. Name one by its id." unless found.one?

        found.sole
      end

      def self.time(value)
        return nil if value.blank?

        Time.zone.iso8601(value.to_s)
      rescue ArgumentError
        raise Refused, "changed_since is not a time Firefight can read. Give it as ISO 8601, such as 2026-10-06T09:00:00Z."
      end
    end
  end
end
