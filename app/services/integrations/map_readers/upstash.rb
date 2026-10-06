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
      GET_DATABASE = "redis_get_database".freeze
      DOMAIN = "upstash.io".freeze
      REDIS_PORT = 6379
      HTTPS_PORT = 443
      REGIONS = %w[us eu].freeze
      ACCOUNT = "upstash".freeze

      def initialize(...)
        super
        @resources = []
        @endpoints = []
      end

      def map
        databases = read(LIST_DATABASES, "Redis databases", {}, "databases", ResourceMap::KIND_DATABASE)
        Array(databases).each { |database| database(database) }
        addresses(Array(databases))
        REGIONS.each do |region|
          users = read(LIST_QSTASH, "QStash of the #{region} region", { Capabilities::Upstash::REGION => region }, "users", ResourceMap::KIND_QUEUE)
          Array(users).first(1).each { |user| qstash(region, user) }
        end
        ResourceMap::Snapshot.new(resources: @resources, gaps: gaps, endpoints: @endpoints)
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

      # Where each database is reached. The Developer API's Database object has endpoint, a slug or a full host, and port
      # (https://upstash.com/docs/devops/developer-api/redis/list_databases). Upstash does not say whether its server's
      # list carries them, so a database listed without one is described with redis_get_database, never asking for its
      # credentials, when that tool is on. Clients connect over TLS on the port, and the REST API answers on HTTPS at the
      # same host. QStash answers on one host for every account, so it has no address of its own.
      def addresses(databases)
        return if workspace.nil?

        missing = []
        databases.each do |database|
          database = described(database) || (missing << database && next) if database["endpoint"].blank?
          address(database)
        end
        return if missing.empty?

        gap("Upstash did not say where #{missing.size} Redis #{'database'.pluralize(missing.size)} #{missing.one? ? 'is' : 'are'} reached" \
            "#{" and #{GET_DATABASE} is switched off" unless on?(GET_DATABASE)}, so settings that name #{missing.one? ? 'it' : 'them'} are not linked.",
            kinds: [], settings: true)
      end

      def described(database)
        return unless on?(GET_DATABASE) && !@describing_refused

        answer = call(GET_DATABASE, { "database_id" => database["database_id"].to_s }, "where #{database['database_name'] || database['database_id']} is reached")
        @describing_refused = answer.nil? || answer["isError"]
        data = @describing_refused ? nil : Capabilities::Answers.data(answer)
        data = data["database"] if data.is_a?(Hash) && data["database"].is_a?(Hash)
        data.is_a?(Hash) && data["endpoint"].present? ? data : nil
      end

      def address(database)
        key = [ PROVIDER, ACCOUNT, ResourceMap::KIND_DATABASE, database["database_id"].to_s ]
        endpoint = database["endpoint"].to_s
        host = endpoint.include?(".") ? endpoint : "#{endpoint}.#{DOMAIN}"
        [ database["port"].presence || REDIS_PORT, HTTPS_PORT ].uniq.each do |port|
          @endpoints << ResourceMap::Endpoint.at(resource: key, host: host, port: port, workspace: workspace)
        end
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
