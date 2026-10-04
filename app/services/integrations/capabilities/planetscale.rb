module Integrations
  module Capabilities
    # PlanetScale answers through the tools its MCP server publishes. A branch's status is planetscale_get_branch, which
    # takes path parameters. Its server logs are planetscale_get_postgres_logs, from planetscale/mcp-server,
    # src/tools/get-postgres-logs.ts, which reads only Postgres branches. A database is answered by its production
    # branch, as the map's reader links it. The logs filter is LogsQL, the query language of the store behind that tool.
    # A quoted phrase matches text, - in front leaves it out and ~ makes it a regular expression, each value quoted the
    # way the tool quotes its own.
    module Planetscale
      extend Adapter

      PROVIDER = SourceLinks::Planetscale::NAME
      PROVIDER_KEY = MapReaders::Planetscale::PROVIDER
      HELD = [ ResourceMap::KIND_DATABASE, ResourceMap::KIND_BRANCH ].freeze
      SUPPORTS = { LOGS => HELD, STATUS => HELD }.freeze
      TOOLS = { LOGS => "planetscale_get_postgres_logs", STATUS => "planetscale_get_branch" }.freeze
      # PlanetScale's tools reach every database the connection sees, far beyond the map, so they stay offered as they are.
      WRAPPED = [].freeze
      # What PlanetScale calls a MySQL database, which runs on Vitess and keeps no server logs a tool reads.
      MYSQL = "mysql".freeze
      ENGINE = "engine".freeze
      LOG_LIMIT = 200
      LOG_MOST = 1_000

      def self.route(key, resource, given, tool: nil, settings: nil)
        database, branch = place(resource)
        case key
        when STATUS
          Route.new(tool_name: TOOLS[STATUS], arguments: { "pathParameters" => { "organization" => resource.account, "database" => database, "branch" => branch } })
        when LOGS then logs(resource, database, branch, given)
        end
      end

      # The database and branch names a resource stands for. A database is asked through its production branch.
      def self.place(resource)
        return resource.external_id.to_s.split("/", 2) if resource.kind == ResourceMap::KIND_BRANCH

        production = ResourceMap::Link.facts.where(to_resource: resource, relation: ResourceMap::RELATION_BRANCH_OF).includes(:from_resource)
                                      .map(&:from_resource).find { |branch| branch.removed_at.nil? && branch.details[ResourceMap::PRODUCTION] }
        raise Unroutable, "The map knows no production branch of #{resource.name}, so name its branch, such as #{resource.name}/main." unless production

        production.external_id.to_s.split("/", 2)
      end

      def self.logs(resource, database, branch, given)
        if engine_of(resource) == MYSQL
          raise Unroutable, "PlanetScale keeps server logs only for Postgres databases, and #{database} is a MySQL (Vitess) database."
        end
        raise Unroutable, "PlanetScale keeps the database server's own logs, so stream must be #{STREAM_APP}." unless given["stream"].in?([ nil, "", STREAM_APP ])

        limit = Answers.limit(given, LOG_MOST, default: LOG_LIMIT)
        filter = [ (quoted(given["text"]) if given["text"].present?), ("-#{quoted(given['exclude'])}" if given["exclude"].present?),
                   ("~#{quoted(given['regex'])}" if given["regex"].present?) ].compact.join(" ")
        arguments = { "organization" => resource.account, "database" => database, "branch" => branch, "limit" => limit }
        arguments["query"] = filter if filter.present?
        Route.new(tool_name: TOOLS[LOGS], arguments: arguments.merge(window(given)),
                  present: ->(result) { Answers.read(result, PROVIDER) { |data| logs_result(resource, "#{database}/#{branch}", data, limit) } })
      end

      # The engine the map read for the database, from the branch's database when the resource is a branch.
      def self.engine_of(resource)
        return resource.details[ENGINE] if resource.kind == ResourceMap::KIND_DATABASE

        database = ResourceMap::Link.facts.where(from_resource: resource, relation: ResourceMap::RELATION_BRANCH_OF).includes(:to_resource).first&.to_resource
        database&.details&.dig(ENGINE)
      end

      # Minutes alone go as the tool's period, such as 30m, so the same request reads the same each time. A start or end
      # goes as from and to, which the tool takes together.
      def self.window(given)
        if given["start"].blank? && given["end"].blank?
          minutes = given["minutes"].to_i.positive? ? [ given["minutes"].to_i, MAX_MINUTES ].min : DEFAULT_MINUTES
          return { "period" => "#{minutes}m" }
        end

        started, ended = Telemetry.range(given, default_minutes: DEFAULT_MINUTES, max_minutes: MAX_MINUTES)
        { "from" => started.utc.iso8601, "to" => ended.utc.iso8601 }
      end

      def self.quoted(text) = "\"#{text.to_s.gsub(/["\\]/) { |character| "\\#{character}" }}\""

      def self.logs_result(resource, branch, data, limit)
        lines = Array(data["logs"]).filter_map do |entry|
          at = Telemetry.parse_time(entry["time"])
          source = [ entry["pod"], ("(#{entry['role']})" if entry["role"]) ].compact.join(" ").presence || branch
          text = [ entry["level"], entry["message"] ].compact_blank.join(" ")
          Telemetry::LogLine.new(at: at, source: source, text: text) if at && text.present?
        end.sort_by(&:at).reverse
        Telemetry.result(Telemetry.logs_text(lines, asked: "branch #{branch}", limit: limit), link: Answers.page(resource, PROVIDER))
      end

      private_class_method :place, :logs, :engine_of, :window, :quoted, :logs_result
    end
  end
end
