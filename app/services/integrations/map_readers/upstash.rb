module Integrations
  module MapReaders
    # Puts Upstash on the resource map. redis_list_databases gives the Redis databases in the connection's account
    # scope, and qstash_list_users the QStash of each region, eu or us. These are the tools Upstash's docs name for its
    # remote MCP server, and the fields are those of the Database and QStashUser objects in Upstash's Developer API.
    # Listings carry no credentials, and qstash_list_users is never asked for them.
    class Upstash < RemoteReader
      PROVIDER = Capabilities::Upstash::PROVIDER_KEY
      NAME = Capabilities::Upstash::PROVIDER
      LIST_DATABASES = "redis_list_databases".freeze
      LIST_QSTASH = "qstash_list_users".freeze
      REGIONS = %w[us eu].freeze
      ACCOUNT = "upstash".freeze

      def initialize(...)
        super
        @resources = []
      end

      def map
        databases = read(LIST_DATABASES, "Redis databases", {}, "databases", ResourceMap::KIND_DATABASE)
        Array(databases).each { |database| database(database) }
        REGIONS.each do |region|
          users = read(LIST_QSTASH, "QStash of the #{region} region", { Capabilities::Upstash::REGION => region }, "users", ResourceMap::KIND_QUEUE)
          Array(users).first(1).each { |user| qstash(region, user) }
        end
        ResourceMap::Snapshot.new(resources: @resources, gaps: gaps)
      end

      private

      def database(database)
        return if database["database_id"].blank?

        @resources << ResourceMap::Found.new(
          provider: PROVIDER, account: ACCOUNT, kind: ResourceMap::KIND_DATABASE, external_id: database["database_id"].to_s,
          name: database["database_name"].presence || database["database_id"].to_s, status: database["state"], url: SourceLinks::Upstash.product(settings, SourceLinks::Upstash::REDIS),
          details: { "engine" => "redis", "region" => database["primary_region"].presence || database["region"], "plan" => database["type"],
                     "read_regions" => database["read_regions"].presence, "eviction" => database["eviction"] }.compact
        )
      end

      def qstash(region, user)
        state = user["state"].presence || (user["active"] == false ? "inactive" : nil)
        @resources << ResourceMap::Found.new(
          provider: PROVIDER, account: ACCOUNT, kind: ResourceMap::KIND_QUEUE, external_id: "qstash-#{region}", name: "QStash #{region}",
          status: state, url: SourceLinks::Upstash.product(settings, SourceLinks::Upstash::QSTASH),
          details: { Capabilities::Upstash::REGION => region, "max_requests_per_day" => user["max_requests_per_day"],
                     "max_retries" => user["max_retries"], "max_dlq_size" => user["max_dlq_size"] }.compact
        )
      end

      # A list of objects, bare or under its name. A region with no QStash answers nothing, which is no gap.
      def read(tool, what, arguments, key, kind)
        data = listing(tool, what, arguments, kinds: [ kind ])
        data = data[key] if data.is_a?(Hash) && data.key?(key)
        data = [ data ] if data.is_a?(Hash) && data.key?("id")
        return data if data.is_a?(Array) && data.all?(Hash)

        gap("Upstash answered the #{what} in a shape Firefight does not read.", kinds: [ kind ]) unless data.nil?
      end
    end
  end
end
