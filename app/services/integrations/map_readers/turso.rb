module Integrations
  module MapReaders
    # Puts Turso on the resource map. list_databases, the tool Turso names for its hosted MCP server, gives the
    # databases the connection's organization or group holds, and a database branched from another is a branch of it.
    # The fields are those of the Database object in Turso's Platform API, plus engine, which Turso's agent skill says
    # the tool adds. A database is grouped on the map by its Turso group.
    class Turso < RemoteReader
      PROVIDER = Capabilities::Turso::PROVIDER_KEY
      NAME = Capabilities::Turso::PROVIDER
      LIST_DATABASES = "list_databases".freeze
      KINDS = [ ResourceMap::KIND_DATABASE, ResourceMap::KIND_BRANCH ].freeze

      def map
        data = listing(LIST_DATABASES, "databases", kinds: KINDS)
        databases = data.is_a?(Hash) ? data["databases"] : data
        unless databases.is_a?(Array) && databases.all?(Hash)
          gap("Turso answered the databases in a shape Firefight does not read.", kinds: KINDS) unless data.nil?
          return ResourceMap::Snapshot.new(resources: [], gaps: gaps)
        end

        found = databases.filter_map { |database| database(database) }
        by_id = found.index_by(&:external_id)
        links = databases.filter_map do |database|
          parent = by_id[database.dig("parent", "id").to_s]
          child = by_id[field(database, "DbId", "id").to_s]
          ResourceMap::FoundLink.new(from: child.key, to: parent.key, relation: ResourceMap::RELATION_BRANCH_OF) if parent && child
        end
        ResourceMap::Snapshot.new(resources: found, links: links)
      end

      private

      def database(database)
        id = field(database, "DbId", "id")
        name = field(database, "Name", "name")
        return if id.blank? || name.blank?

        blocked = [ ("reads" if database["block_reads"]), ("writes" if database["block_writes"]) ].compact
        ResourceMap::Found.new(
          provider: PROVIDER, account: database["group"].presence || "default",
          kind: database["parent"].present? ? ResourceMap::KIND_BRANCH : ResourceMap::KIND_DATABASE,
          external_id: id.to_s, name: name.to_s, status: blocked.any? ? "#{blocked.join(' and ')} blocked" : "active",
          details: { "engine" => database["engine"], "region" => database["primaryRegion"], "hostname" => field(database, "Hostname", "hostname"),
                     "delete_protection" => database["delete_protection"] }.compact
        )
      end

      def field(database, *names) = names.filter_map { |name| database[name].presence }.first
    end
  end
end
