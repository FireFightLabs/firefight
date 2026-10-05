module Integrations
  module Capabilities
    # ClickHouse Cloud answers through its remote MCP server. ClickHouse's docs list the server's tools with their
    # parameters, in products/cloud/features/ai-ml/remote-mcp. get_service_details takes organizationId and serviceId,
    # and run_select_query takes serviceId and a query it runs read only. A service's logs, queries and metrics live in
    # its system tables text_log, query_log and metric_log, as ClickHouse documents them under reference/system-tables.
    # Firefight writes one SELECT for each, every value a quoted literal, so the agent's words never become SQL. Each of
    # those tables is kept per replica and gains a new version after an upgrade, so they are read across every replica
    # and version with clusterAllReplicas and merge, as the docs' section on system tables in ClickHouse Cloud says.
    module Clickhouse
      extend Adapter

      PROVIDER = "ClickHouse".freeze
      PROVIDER_KEY = "clickhouse".freeze
      QUERY = "run_select_query".freeze
      DETAILS = "get_service_details".freeze
      SUPPORTS = {
        LOGS => [ ResourceMap::KIND_DATABASE ], METRICS => [ ResourceMap::KIND_DATABASE ],
        STATUS => [ ResourceMap::KIND_DATABASE ], ERRORS => [ ResourceMap::KIND_DATABASE ]
      }.freeze
      TOOLS = { LOGS => QUERY, METRICS => QUERY, ERRORS => QUERY, STATUS => DETAILS }.freeze
      # run_select_query reads far more than any capability, so only the service's details are answered one to one.
      WRAPPED = [ DETAILS ].freeze
      ORGANIZATION = "organizationId".freeze
      SERVICE = "serviceId".freeze
      SQL = "query".freeze
      LOG_LIMIT = 200
      ERROR_LIMIT = 50
      ROWS = 10_000
      TEXT_LIMIT = 500
      SHOWN = 300
      POINTS = 60
      BUCKETS = [ 1, 5, 15, 60, 360, 1440 ].freeze
      # Stream app reads what the server printed, and stream requests the queries clients sent it.
      STREAMS = { nil => "text_log", STREAM_APP => "text_log", "requests" => "query_log" }.freeze
      # Each metric's metric_log column, how a bucket of readings adds up and how that becomes the unit shown. A
      # ProfileEvent_ column counts events in a reading, and a CurrentMetric_ column is a level.
      Metric = Data.define(:column, :aggregate, :title, :unit, :convert)
      METRICS_READ = {
        "requests" => Metric.new(column: "ProfileEvent_Query", aggregate: "sum", title: "Queries", unit: "per minute",
                                 convert: ->(value, minutes) { value / minutes }),
        "errors" => Metric.new(column: "ProfileEvent_FailedQuery", aggregate: "sum", title: "Failed queries", unit: "per minute",
                               convert: ->(value, minutes) { value / minutes }),
        "cpu" => Metric.new(column: "ProfileEvent_OSCPUVirtualTimeMicroseconds", aggregate: "sum", title: "CPU", unit: "vCPU",
                            convert: ->(value, minutes) { value / (minutes * 60 * 1_000_000.0) }),
        "memory" => Metric.new(column: "CurrentMetric_MemoryTracking", aggregate: "avg", title: "Memory", unit: "MB",
                               convert: ->(value, _minutes) { value / 1_048_576.0 }),
        "network_in" => Metric.new(column: "ProfileEvent_NetworkReceiveBytes", aggregate: "sum", title: "Network in", unit: "KB/s",
                                   convert: ->(value, minutes) { value / (minutes * 60 * 1024.0) }),
        "network_out" => Metric.new(column: "ProfileEvent_NetworkSendBytes", aggregate: "sum", title: "Network out", unit: "KB/s",
                                    convert: ->(value, minutes) { value / (minutes * 60 * 1024.0) }),
        "tcp_connections" => Metric.new(column: "CurrentMetric_TCPConnection", aggregate: "avg", title: "Native protocol connections",
                                        unit: "count", convert: ->(value, _minutes) { value })
      }.freeze
      DEFAULT_METRICS = %w[requests errors cpu memory].freeze

      def self.route(key, resource, given, tool: nil, settings: nil)
        case key
        when STATUS
          Route.new(tool_name: DETAILS, arguments: { ORGANIZATION => organization_of(resource), SERVICE => resource.external_id })
        when LOGS then logs(resource, given)
        when METRICS then metrics(resource, given)
        when ERRORS then errors(resource, given)
        end
      end

      # The organization a service is in, which the map's reader keeps as the resource's account.
      def self.organization_of(resource)
        resource.account.presence || raise(Unroutable, "The ClickHouse organization of #{resource.name} is not known, so it cannot be asked for this.")
      end

      def self.logs(resource, given)
        stream = given["stream"].presence
        unless STREAMS.key?(stream)
          raise Unroutable, "ClickHouse keeps what the server printed (stream app) and the queries clients sent it (stream requests), nothing else."
        end

        limit = Answers.limit(given, LOG_LIMIT)
        from, to = range_sql(given)
        table = STREAMS.fetch(stream)
        sql = if table == "text_log"
          "SELECT event_time_microseconds AS at, hostname AS replica, level, logger_name, message FROM #{system(table)} " \
            "WHERE #{window(from, to)}#{filters('message', given)} ORDER BY event_time_microseconds DESC LIMIT #{limit}"
        else
          "SELECT event_time_microseconds AS at, hostname AS replica, type, user, query_kind, query_duration_ms, read_rows, " \
            "memory_usage, errorCodeToName(exception_code) AS error, left(query, #{SHOWN}) AS query, left(exception, #{SHOWN}) AS exception " \
            "FROM #{system(table)} WHERE #{window(from, to)} AND type != 'QueryStart' AND is_initial_query = 1#{filters('query', given)} " \
            "ORDER BY event_time_microseconds DESC LIMIT #{limit}"
        end
        Route.new(tool_name: QUERY, arguments: { SERVICE => resource.external_id, SQL => sql },
                  present: ->(result) { read(result) { |rows| logs_result(result, resource, rows, table, limit) } })
      end

      def self.metrics(resource, given)
        metric_names(given, METRICS_READ.transform_values(&:column), PROVIDER)
        names = Array(given["metrics"]).map(&:to_s).uniq.presence || DEFAULT_METRICS
        started, ended = Answers.range(given)
        minutes = bucket_minutes(started, ended)
        from, to = range_sql(given)
        Route.new(tool_name: QUERY, arguments: { SERVICE => resource.external_id, SQL => metrics_sql(names, minutes, from, to) },
                  present: ->(result) { read(result) { |rows| metrics_result(result, resource, rows, names, minutes, started, ended) } })
      end

      # One read of metric_log for the metrics asked, a row per bucket and replica.
      def self.metrics_sql(names, minutes, from, to)
        columns = names.map { |name| "#{METRICS_READ.fetch(name).aggregate}(#{METRICS_READ.fetch(name).column}) AS #{name}" }
        "SELECT toStartOfInterval(event_time, INTERVAL #{minutes} MINUTE) AS at, hostname AS replica, #{columns.join(', ')} " \
          "FROM #{system('metric_log')} WHERE #{window(from, to)} GROUP BY at, replica ORDER BY at LIMIT #{ROWS}"
      end

      def self.errors(resource, given)
        limit = Answers.limit(given, ERROR_LIMIT)
        from, to = range_sql(given)
        sql = "SELECT errorCodeToName(exception_code) AS error, exception_code AS code, count() AS times, min(event_time) AS first_seen, " \
              "max(event_time) AS last_seen, any(left(exception, #{SHOWN})) AS example FROM #{system('query_log')} " \
              "WHERE #{window(from, to)} AND exception_code != 0#{filters('exception', given.slice('text'))} " \
              "GROUP BY exception_code ORDER BY times DESC LIMIT #{limit}"
        Route.new(tool_name: QUERY, arguments: { SERVICE => resource.external_id, SQL => sql },
                  present: ->(result) { read(result) { |rows| errors_result(result, resource, rows) } })
      end

      # A system table across every replica and every version an upgrade left behind.
      def self.system(table) = "clusterAllReplicas('default', merge('system', '^#{table}'))"

      # event_date leads every system log table's sorting key, so it bounds what is scanned before event_time narrows it.
      def self.window(from, to) = "event_date >= toDate(#{from}) AND event_time >= #{from} AND event_time <= #{to}"

      # The time asked for as SQL. Minutes alone stay relative to now, so the same request reads the same each time and
      # an approved call matches its retry. A start or end is an absolute time.
      def self.range_sql(given)
        ended = Telemetry.parse_time(given["end"])
        started = Telemetry.parse_time(given["start"])
        minutes = Answers.minutes(given.except("start", "end"))
        to = ended ? time_literal(ended) : "now()"
        from = started ? time_literal([ started, (ended || Time.current) - MAX_MINUTES.minutes ].max) : "#{to} - INTERVAL #{minutes} MINUTE"
        [ from, to ]
      end

      def self.time_literal(time) = "toDateTime(#{literal(time.utc.strftime('%Y-%m-%d %H:%M:%S'))}, 'UTC')"

      # text, regex and exclude as conditions on one column. match takes RE2, which cannot run away.
      def self.filters(column, given)
        conditions = []
        conditions << "position(#{column}, #{literal(given['text'])}) > 0" if given["text"].present?
        conditions << "match(#{column}, #{literal(given['regex'])})" if given["regex"].present?
        conditions << "position(#{column}, #{literal(given['exclude'])}) = 0" if given["exclude"].present?
        conditions.map { |condition| " AND #{condition}" }.join
      end

      # A string as a ClickHouse literal, with the backslash and quote that could end it escaped.
      def self.literal(value)
        text = value.to_s
        raise Unroutable, "Keep each filter under #{TEXT_LIMIT} characters." if text.length > TEXT_LIMIT

        "'#{text.gsub(/[\\']/) { |character| "\\#{character}" }}'"
      end

      def self.bucket_minutes(started, ended)
        wanted = (ended - started) / 60.0 / POINTS
        BUCKETS.find { |minutes| minutes >= wanted } || BUCKETS.last
      end

      # The rows of a query's answer, or the answer as it came when it is an error or in a shape Firefight does not read.
      def self.read(result, &) = Answers.read(result, PROVIDER) { |body| (rows = rows_of(body)) && yield(rows) }

      # Rows from the shapes a ClickHouse query answers in, which are columns beside rows, the JSON format's data, or a
      # list of objects, inside the Cloud API's result envelope or not.
      def self.rows_of(data)
        data = data["result"] if data.is_a?(Hash) && data.key?("result")
        case data
        when Array then data.all?(Hash) ? data : nil
        when Hash
          return data["data"] if data["data"].is_a?(Array) && data["data"].all?(Hash)
          return unless data["columns"].is_a?(Array) && data["rows"].is_a?(Array)

          names = data["columns"].map { |column| column.is_a?(Hash) ? column["name"] : column }
          data["rows"].map { |row| names.zip(Array(row)).to_h }
        end
      end

      def self.logs_result(result, resource, rows, table, limit)
        lines = rows.filter_map do |row|
          at = Telemetry.parse_time(row["at"])
          next unless at

          text = if table == "text_log"
            "#{row['level']} #{row['logger_name']}: #{row['message']}"
          else
            failed = row["error"].present? && row["error"] != "OK"
            [ row["type"], row["user"], row["query_kind"], "#{row['query_duration_ms']} ms", "#{row['read_rows']} rows read",
              ("#{row['error']}: #{row['exception']}" if failed), row["query"] ].compact.join(", ")
          end
          Telemetry::LogLine.new(at: at, source: row["replica"].to_s, text: text)
        end
        what = table == "text_log" ? "what #{resource.name} printed" : "the queries #{resource.name} ran"
        Answers.presented(result, Telemetry.logs_text(lines, asked: what, limit: limit))
      end

      def self.metrics_result(result, resource, rows, names, minutes, started, ended)
        by_replica = rows.group_by { |row| row["replica"].to_s }
        charts = names.map do |name|
          metric = METRICS_READ.fetch(name)
          series = by_replica.map do |replica, readings|
            points = readings.filter_map do |row|
              at = Telemetry.parse_time(row["at"])
              [ at, metric.convert.call(row[name].to_f, minutes) ] if at && !row[name].nil?
            end
            Telemetry::Series.new(label: replica, points: points.sort_by(&:first))
          end
          Telemetry::Chart.new(title: "#{metric.title} of #{resource.name}", unit: metric.unit, series: series, from: started, to: ended)
        end
        cut = rows.size >= ROWS ? " ClickHouse answered with its most of #{ROWS} rows, so later points may be missing. Narrow the range to see them." : ""
        Answers.presented(result, "#{Telemetry.charts_text(charts)}\nRead every #{minutes} minutes, a series per replica.#{cut}", charts: charts)
      end

      def self.errors_result(result, resource, rows)
        return Answers.presented(result, "No query failed on #{resource.name} in that range.") if rows.empty?

        lines = rows.map do |row|
          "#{row['error']} (code #{row['code']}): #{row['times']} times, first #{row['first_seen']}, last #{row['last_seen']}. #{row['example'].to_s.squish}"
        end
        Answers.presented(result, "Queries that failed on #{resource.name}, by error, most frequent first.\n#{lines.join("\n")}")
      end

      private_class_method :organization_of, :logs, :metrics, :errors, :window, :range_sql, :filters,
                           :bucket_minutes, :read, :logs_result, :metrics_result, :errors_result
    end
  end
end
