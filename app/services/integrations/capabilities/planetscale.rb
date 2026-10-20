module Integrations
  module Capabilities
    # PlanetScale answers through the tools its MCP server publishes. A branch's status is planetscale_get_branch, which
    # takes path parameters. Its server logs are planetscale_get_postgres_logs, from planetscale/mcp-server,
    # src/tools/get-postgres-logs.ts, which reads only Postgres branches. A database is answered by its production
    # branch, as the map's reader links it. The logs filter is LogsQL, the query language of the store behind that tool.
    # A quoted phrase matches text, - in front leaves it out and ~ makes it a regular expression, each value quoted the
    # way the tool quotes its own. Metrics and errors are the server's branch metrics and query error patterns, from
    # get-branch-metrics.ts and query-errors.ts. Deploy requests, a branch's changes, a revert and a resize are the tools
    # of the pack beside the server (Packs::Planetscale), which reaches PlanetScale's API.
    module Planetscale
      extend Adapter

      PROVIDER = SourceLinks::Planetscale::NAME
      PROVIDER_KEY = MapReaders::Planetscale::PROVIDER
      HELD = [ ResourceMap::KIND_DATABASE, ResourceMap::KIND_BRANCH ].freeze
      LIST_DEPLOY_REQUESTS = "planetscale_list_deploy_requests".freeze
      GET_DEPLOY_REQUEST = "planetscale_get_deploy_request".freeze
      LIST_BRANCH_CHANGES = "planetscale_list_branch_changes".freeze
      REVERT_DEPLOY_REQUEST = "planetscale_revert_deploy_request".freeze
      RESIZE_BRANCH = "planetscale_resize_branch".freeze
      BRANCH_METRICS = "planetscale_get_branch_metrics".freeze
      ERROR_PATTERNS = "planetscale_list_query_error_patterns".freeze
      SUPPORTS = [ LOGS, STATUS, HISTORY, DEPLOYS, ROLLBACK, METRICS, ERRORS, SCALE ].index_with { HELD }.freeze
      TOOLS = {
        LOGS => "planetscale_get_postgres_logs", STATUS => "planetscale_get_branch", HISTORY => [ LIST_DEPLOY_REQUESTS, GET_DEPLOY_REQUEST, LIST_BRANCH_CHANGES ],
        DEPLOYS => LIST_DEPLOY_REQUESTS, ROLLBACK => REVERT_DEPLOY_REQUEST, METRICS => BRANCH_METRICS, ERRORS => ERROR_PATTERNS, SCALE => RESIZE_BRANCH
      }.freeze
      # PlanetScale's tools reach every database the connection sees, far beyond the map, so they stay offered as they are.
      WRAPPED = [].freeze
      # What PlanetScale calls a MySQL database, which runs on Vitess and keeps no server logs a tool reads.
      MYSQL = "mysql".freeze
      ENGINE = "engine".freeze
      LOG_LIMIT = 200
      LOG_MOST = 1_000
      # A run history asked by one of these words reads the changes to a branch's size and settings, and otherwise its
      # deploy requests, so a schema change stays a deploy request.
      CHANGES = /resiz|\bsize|config|branch chang/i
      # The metrics get_branch_metrics keeps for each engine under its own names (planetscale/mcp-server,
      # src/tools/get-branch-metrics.ts), a Postgres branch's as percentages and a Vitess one's by its primary tablet.
      METRIC_MAP = {
        MapReaders::Planetscale::POSTGRES => { "cpu" => "planetscale_primary_pods_cpu_util_percentages",
                                               "memory" => "planetscale_primary_pods_mem_util_percentages", "disk" => "planetscale_volume_usage_percentages" },
        MYSQL => { "cpu" => "primary_cpu_usage", "memory" => "primary_memory_usage", "disk" => "shard_storage_usage" }
      }.freeze
      # The periods get_branch_metrics and the query error tools take, in minutes.
      PERIODS = { "15m" => 15, "1h" => 60, "3h" => 180, "6h" => 360, "12h" => 720, "1d" => 1_440, "2d" => 2_880, "7d" => 10_080, "8d" => 11_520 }.freeze
      # The query error tools read at most this window, and quietly read their default one past it (src/lib/insights-tools.ts).
      ERROR_WINDOW_HOURS = 25
      ERROR_LIMIT = 25
      ERROR_MOST = 100

      def self.takes_plan? = true

      def self.route(key, resource, given, tool: nil, settings: nil)
        case key
        when HISTORY then history(resource, given)
        when DEPLOYS
          Route.new(tool_name: LIST_DEPLOY_REQUESTS, arguments: requests_of(resource).merge("state" => "deployed", "limit" => given["limit"]).compact_blank)
        when ROLLBACK then rollback(resource, given)
        when SCALE then scale(resource, given)
        else
          database, branch = place(resource)
          case key
          when STATUS
            Route.new(tool_name: TOOLS[STATUS], arguments: { "pathParameters" => { "organization" => resource.account, "database" => database, "branch" => branch } })
          when LOGS then logs(resource, database, branch, given)
          when METRICS then metrics(resource, database, branch, given)
          when ERRORS then errors(resource, database, branch, given)
          end
        end
      end

      # A database's deploy requests, a branch's into it, one by its number, or a branch's changes to its size and settings.
      def self.history(resource, given)
        if given["name"].to_s.match?(CHANGES)
          database, branch = place(resource)
          arguments = { "organization" => resource.account, "database" => database, "branch" => branch }
          return Route.new(tool_name: LIST_BRANCH_CHANGES, arguments: arguments, present: presenter("the changes to #{database}/#{branch}", given.except("name")))
        end

        arguments = requests_of(resource)
        if given["run"].present?
          number = given["run"].to_s.strip.delete_prefix("#")
          return Route.new(tool_name: GET_DEPLOY_REQUEST, arguments: arguments.except("into_branch").merge("number" => number),
                           present: presenter("deploy request ##{number}", given.except("name")))
        end

        Route.new(tool_name: LIST_DEPLOY_REQUESTS, arguments: arguments.merge("limit" => given["limit"]).compact_blank,
                  present: presenter("the deploy requests of #{resource.name}", given.except("name")))
      end

      # The runs a pack tool answered with, kept to the one asked for by its id.
      def self.presenter(what, given)
        lambda do |result|
          runs = History.runs_of(result)
          next result unless runs

          runs = runs.select { |run| run.named?(given["run"]) } if given["run"].present?
          History.result(runs, what: what, link: RunHistory.link_of(result), limit: Answers.limit(given, History::LIMIT))
        end
      end

      # A database's deploy requests, or a branch's, the ones deployed into it.
      def self.requests_of(resource)
        if resource.kind == ResourceMap::KIND_BRANCH
          database, branch = resource.external_id.to_s.split("/", 2)
          return { "organization" => resource.account, "database" => database, "into_branch" => branch }
        end

        { "organization" => resource.account, "database" => resource.external_id }
      end

      # Undoes a deploy request by its number, while PlanetScale keeps its revert window open.
      def self.rollback(resource, given)
        number = target(given).delete_prefix("#")
        unless number.match?(/\A\d+\z/)
          raise Unroutable, "PlanetScale rolls a schema back by reverting the deploy request that changed it, so say its number, as recent_deploys gives it."
        end

        database = requests_of(resource)["database"]
        Route.new(tool_name: REVERT_DEPLOY_REQUEST, arguments: { "organization" => resource.account, "database" => database, "number" => number.to_i })
      end

      # A Postgres branch is sized by its cluster, plan here, and its replicas, instances here. A Vitess database is sized
      # per keyspace, which the capability cannot name.
      def self.scale(resource, given)
        if engine_of(resource) == MYSQL
          raise Unroutable, "PlanetScale sizes a Vitess database per keyspace, so resize it with #{RESIZE_BRANCH}, naming the keyspace."
        end

        database, branch = place(resource)
        arguments = { "organization" => resource.account, "database" => database, "branch" => branch }
        arguments["cluster_size"] = given[PLAN_ARG].to_s.strip if given[PLAN_ARG].present?
        arguments["replicas"] = instances(given) if given["instances"].present?
        Route.new(tool_name: RESIZE_BRANCH, arguments: arguments)
      end

      def self.metrics(resource, database, branch, given)
        mapping = METRIC_MAP.fetch(engine_of(resource), METRIC_MAP.fetch(MapReaders::Planetscale::POSTGRES))
        names = Array(given["metrics"]).map(&:to_s).uniq.presence || mapping.keys
        wanted = metric_names(given.merge("metrics" => names), mapping, PROVIDER)
        started, ended = Answers.range(given)
        arguments = { "organization" => resource.account, "database" => database, "branch" => branch, "view" => "series", "metrics" => wanted,
                      "include_points" => true }.merge(period_or_range(given))
        Route.new(tool_name: BRANCH_METRICS, arguments: arguments,
                  present: ->(result) { Answers.read(result, PROVIDER) { |data| metrics_result(result, resource, data, mapping.invert, started, ended) } })
      end

      def self.errors(resource, database, branch, given)
        minutes = Answers.minutes(given)
        started, ended = Answers.range(given)
        if (ended - started) > ERROR_WINDOW_HOURS.hours
          raise Unroutable, "PlanetScale reads at most #{ERROR_WINDOW_HOURS} hours of failing queries a call. Ask for a shorter range."
        end

        window = minutes && PERIODS.key(minutes) ? { "period" => PERIODS.key(minutes) } : { "from" => started.utc.iso8601, "to" => ended.utc.iso8601 }
        arguments = { "organization" => resource.account, "database" => database, "branch" => branch,
                      "limit" => Answers.limit(given, ERROR_MOST, default: ERROR_LIMIT) }.merge(window)
        arguments["query"] = given["text"] if given["text"].present?
        Route.new(tool_name: ERROR_PATTERNS, arguments: arguments,
                  present: ->(result) { Answers.read(result, PROVIDER) { |data| errors_result(result, "#{database}/#{branch}", data) } })
      end

      # Minutes alone as the shortest period that reaches back to them, so the same request reads the same each time, and a
      # start or end as from and to.
      def self.period_or_range(given)
        minutes = Answers.minutes(given)
        return { "period" => PERIODS.find { |_period, length| length >= minutes }&.first || PERIODS.keys.last } if minutes

        started, ended = Answers.range(given)
        { "from" => started.utc.iso8601, "to" => ended.utc.iso8601 }
      end

      # One chart per metric, a series per pod, shard or role the tool labelled, from its [unix time, value] points.
      def self.metrics_result(result, resource, data, names, started, ended)
        rows = data.is_a?(Hash) ? data["series"] : nil
        return nil unless rows.is_a?(Array)

        charts = rows.group_by { |row| row["metric"] }.filter_map do |metric, series|
          name = names[metric] || next
          drawn = series.map do |row|
            label = row["labels"].to_h.values.compact_blank.join(" ").presence || resource.name
            points = Array(row["points"]).filter_map { |at, value| [ Answers.time_of(at), value.to_f ] if at && !value.nil? }.sort_by(&:first)
            Telemetry::Series.new(label: label, points: points)
          end
          unit = series.first["unit"].presence || (metric.include?("percentage") ? "%" : "value")
          Telemetry::Chart.new(title: "#{name} of #{resource.name}", unit: unit, series: drawn, from: started, to: ended, link: Answers.linked(result))
        end
        Answers.presented(result, Telemetry.charts_text(charts), charts: charts)
      end

      def self.errors_result(result, branch, data)
        patterns = data.is_a?(Hash) ? data["patterns"] : nil
        return nil unless patterns.is_a?(Array)
        return Answers.presented(result, "No queries failed on #{branch} in that range.") if patterns.empty?

        lines = patterns.map do |pattern|
          "#{pattern['error_count']} times, last #{pattern['started_at']}: #{pattern['error_message'].to_s.squish.truncate(300)} (fingerprint #{pattern['error_fingerprint']})"
        end
        cut = data["truncated"] ? " Only the first #{patterns.size} were returned, so ask for more or a shorter range." : ""
        Answers.presented(result, "Failing queries on #{branch}, by error, most first.#{cut} planetscale_list_query_error_executions reads " \
                                  "the runs behind a fingerprint.\n#{lines.join("\n")}")
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
        minutes = Answers.minutes(given)
        return { "period" => "#{minutes}m" } if minutes

        started, ended = Answers.range(given)
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

      private_class_method :place, :logs, :engine_of, :window, :quoted, :logs_result, :history, :presenter, :requests_of, :rollback, :scale, :metrics,
                           :errors, :period_or_range, :metrics_result, :errors_result
    end
  end
end
