module Integrations
  module MapReaders
    # Puts Upstash on the resource map. redis_list_databases gives the Redis databases in the connection's account
    # scope, and qstash_list_users the QStash of each region, eu or us. These are the tools Upstash's docs name for its
    # remote MCP server, and the fields are those of the Database and QStashUser objects in Upstash's Developer API.
    # Listings carry no credentials, and qstash_list_users is never asked for them.
    #
    # A database's id is Upstash's own and unique, but every account has a QStash in each region, so a QStash is keyed by
    # its QStashUser id, which is the account's QStash in that region. Keyed by region alone, two Upstash accounts' QStash
    # were one resource on the map. A listing without the id is keyed by the region and the connection instead.
    #
    # Upstash keeps no list of workflows, only their runs, so a workflow is on the map once a run of it is among the latest
    # logs_list answers with service workflow, read as the Workflow API's WorkflowRun, keyed by its region's QStash and
    # its address. Boxes come from box_account's summary, which lists each active box, read as the Box SDK's BoxData.
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
      LIST_LOGS = Capabilities::Upstash::LIST_LOGS
      BOX_ACCOUNT = "box_account".freeze
      # The box_account action that lists each active box, as Upstash's MCP docs name it.
      BOX_SUMMARY = "summary".freeze
      # Pages of workflow runs read for each region, ten runs a page.
      WORKFLOW_PAGES = 5
      CURSOR = "cursor".freeze

      def initialize(...)
        super
        @resources = []
        @endpoints = []
        @links = []
      end

      def map
        databases = read(LIST_DATABASES, "Redis databases", {}, "databases", ResourceMap::KIND_DATABASE)
        Array(databases).each { |database| database(database) }
        addresses(Array(databases))
        REGIONS.each do |region|
          users = read(LIST_QSTASH, "QStash of the #{region} region", { Capabilities::Upstash::REGION => region }, "users", ResourceMap::KIND_QUEUE)
          Array(users).first(1).each { |user| workflows(region, qstash(region, user)) }
        end
        boxes
        ResourceMap::Snapshot.new(resources: @resources, links: @links, gaps: gaps, endpoints: @endpoints)
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
        found = ResourceMap::Found.new(
          provider: PROVIDER, account: ACCOUNT, kind: ResourceMap::KIND_QUEUE, external_id: qstash_id(region, user), name: "QStash #{region}",
          status: state, url: SourceLinks::Upstash.product(settings, SourceLinks::Upstash::QSTASH),
          details: { Capabilities::Upstash::REGION => region, "max_requests_per_day" => user["max_requests_per_day"],
                     "max_retries" => user["max_retries"], "max_dlq_size" => user["max_dlq_size"] }.compact
        )
        @resources << found
        found
      end

      def qstash_id(region, user)
        user["id"].present? ? "qstash-#{user['id']}" : [ "qstash", region, settings&.connection_id ].compact.join("-")
      end

      # Each workflow with a run among the region's latest, part of the region's QStash. Only a server whose logs_list
      # takes a service reads workflow runs. Runs past the pages read are no gap, since a busy account always has more,
      # and a gap would keep the sweep from taking anything away. A workflow none of them ran leaves the map until it runs.
      def workflows(region, qstash)
        return unless on?(LIST_LOGS) && parameters(LIST_LOGS).key?(Capabilities::Upstash::SERVICE)

        arguments = { Capabilities::Upstash::REGION => region, Capabilities::Upstash::SERVICE => Capabilities::Upstash::WORKFLOW }
        what = "workflow runs of the #{region} region"
        runs = []
        pages = 0
        loop do
          data = listing(LIST_LOGS, what, arguments, kinds: [ ResourceMap::KIND_WORKFLOW ])
          listed = objects(data, what, kinds: [ ResourceMap::KIND_WORKFLOW ], key: "runs")
          break unless listed

          runs.concat(listed)
          pages += 1
          cursor = data.is_a?(Hash) ? data[CURSOR].presence : nil
          break unless cursor && pages < WORKFLOW_PAGES && parameters(LIST_LOGS).key?(CURSOR)

          arguments = arguments.merge(CURSOR => cursor)
        end
        runs.group_by { |run| run["workflowUrl"].to_s }.each { |url, of_url| workflow(region, qstash, url, of_url) if url.match?(%r{\Ahttps?://}) }
      end

      def workflow(region, qstash, url, runs)
        newest = runs.max_by { |run| run["workflowRunCreatedAt"].to_i }
        found = ResourceMap::Found.new(
          provider: PROVIDER, account: ACCOUNT, kind: ResourceMap::KIND_WORKFLOW, external_id: "#{qstash.external_id}/#{url}",
          name: url.sub(%r{\Ahttps?://}, ""), url: SourceLinks::Upstash.product(settings, SourceLinks::Upstash::WORKFLOW),
          details: { Capabilities::Upstash::REGION => region, Capabilities::Upstash::WORKFLOW_URL => url, "last_run" => newest["workflowState"] }.compact
        )
        @resources << found
        @links << ResourceMap::FoundLink.new(from: found.key, to: qstash.key, relation: ResourceMap::RELATION_PART_OF)
      end

      # Each active box, from box_account's summary when the connected tool offers it. Upstash publishes no address of a
      # box's page, so none is linked.
      def boxes
        return unless on?(BOX_ACCOUNT) && Array(parameters(BOX_ACCOUNT).dig(Capabilities::Upstash::ACTION, "enum")).include?(BOX_SUMMARY)

        kinds = [ ResourceMap::KIND_VIRTUAL_MACHINE ]
        data = listing(BOX_ACCOUNT, "Boxes", { Capabilities::Upstash::ACTION => BOX_SUMMARY }, kinds: kinds)
        listed = data.is_a?(Hash) ? data["boxes"] : data
        return if data.nil?
        return gap("Upstash answered the Boxes in a shape Firefight does not read.", kinds: kinds) unless listed.is_a?(Array) && listed.all?(Hash)

        listed.each do |box|
          next if box["id"].blank?

          @resources << ResourceMap::Found.new(
            provider: PROVIDER, account: ACCOUNT, kind: ResourceMap::KIND_VIRTUAL_MACHINE, external_id: box["id"].to_s,
            name: box["name"].presence || box["id"].to_s, status: box["status"],
            details: { "size" => box["size"], "runtime" => box["runtime"], "keep_alive" => box["keep_alive"], "agent" => box["agent"].presence }.compact
          )
        end
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
