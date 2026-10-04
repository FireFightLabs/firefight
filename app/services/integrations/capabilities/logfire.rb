module Integrations
  module Capabilities
    # Pydantic Logfire watches what other connections run, so it answers logs, traces, errors and metrics for a resource
    # on the map by its service_name, which is the resource's name. Every answer is one SQL query through query_run, the
    # query tool of Logfire's remote MCP server. Its arguments (query, min_timestamp, max_timestamp) are from Pydantic's
    # own skill (pydantic/skills, plugins/logfire/skills/logfire-query/SKILL.md), the records and metrics columns,
    # level_name and time_bucket from Logfire's SQL reference (pydantic/logfire, docs/reference/sql.md), and strpos and
    # the ~ regular expression match from Apache DataFusion, the SQL engine that reference names. The cpu metric is
    # process.cpu.utilization, which logfire.instrument_system_metrics sends by default
    # (logfire-sdk/logfire/_internal/integrations/system_metrics.py, BASIC_CONFIG), as a fraction of every core.
    module Logfire
      extend Adapter

      PROVIDER_KEY = "logfire".freeze
      NAME = "Logfire".freeze
      WATCHED = Adapter::APP_KINDS
      SUPPORTS = {}.freeze
      OBSERVES = { LOGS => WATCHED, METRICS => WATCHED, TRACES => WATCHED, ERRORS => Adapter::ERROR_KINDS }.freeze
      QUERY_RUN = "query_run".freeze
      TOOLS = { LOGS => QUERY_RUN, METRICS => QUERY_RUN, TRACES => QUERY_RUN, ERRORS => QUERY_RUN }.freeze
      # query_run reads every service Logfire holds, far beyond the map, so it stays offered as it is.
      WRAPPED = [].freeze

      LOG_LIMIT = 200
      TRACE_LIMIT = 50
      ERROR_LIMIT = 50
      POINTS = 60
      MIN_STEP = 60
      # Each metric as the SQL that reads it per bucket. Requests and responses come from the HTTP status code Logfire
      # keeps on a server span, cpu from the metrics table, as a percentage.
      METRICS_SQL = {
        "requests" => [ "records", "start_timestamp", "count(*)", "http_response_status_code IS NOT NULL" ],
        "http_4xx" => [ "records", "start_timestamp", "count(*)", "http_response_status_code >= 400 AND http_response_status_code < 500" ],
        "http_5xx" => [ "records", "start_timestamp", "count(*)", "http_response_status_code >= 500" ],
        "cpu" => [ "metrics", "recorded_timestamp", "avg(scalar_value) * 100", "metric_name = 'process.cpu.utilization'" ]
      }.freeze
      COUNTED = %w[requests http_4xx http_5xx].freeze
      METRIC_TITLES = { "requests" => "Requests", "http_4xx" => "4xx responses", "http_5xx" => "5xx responses", "cpu" => "CPU" }.freeze
      METRIC_UNITS = { "requests" => "per minute", "http_4xx" => "per minute", "http_5xx" => "per minute", "cpu" => "%" }.freeze

      # A stream other than what the app printed is the platform's, and so is any metric Logfire does not keep the same
      # way for every service.
      def self.accepts?(key, given, settings: nil)
        case key
        when METRICS
          names = Array(given["metrics"]).map(&:to_s)
          names.any? && (names - METRICS_SQL.keys).empty?
        when LOGS then given["stream"].in?([ nil, "", STREAM_APP ])
        else true
        end
      end

      def self.route_refusal(key, resource, given, settings: nil)
        return if accepts?(key, given)
        return "Logfire keeps only #{METRICS_SQL.keys.join(', ')} the same way for every service. Ask the platform that runs #{resource.name} for the rest." if key == METRICS

        "Logfire holds what an app sends it, so stream must be #{STREAM_APP}. Ask the platform that runs #{resource.name} for the rest."
      end

      def self.route(key, resource, given, tool:, settings: nil)
        refusal = route_refusal(key, resource, given)
        raise Unroutable, refusal if refusal

        case key
        when LOGS then logs(resource, given, tool)
        when METRICS then metrics(resource, given, tool)
        when TRACES then traces(resource, given, tool)
        when ERRORS then errors(resource, given, tool)
        end
      end

      def self.logs(resource, given, tool)
        limit = Answers.limit(given, LOG_LIMIT)
        filters = [ "service_name = #{quoted(resource.name)}" ]
        filters << "strpos(message, #{quoted(given['text'])}) > 0" if given["text"].present?
        filters << "message ~ #{quoted(given['regex'])}" if given["regex"].present?
        filters << "strpos(message, #{quoted(given['exclude'])}) = 0" if given["exclude"].present?
        sql = "SELECT start_timestamp, level_name(level) AS level, span_name, message FROM records WHERE #{filters.join(' AND ')} " \
              "ORDER BY start_timestamp DESC LIMIT #{limit}"
        call(sql, given, tool) { |rows, result| logs_result(resource, rows, limit, result) }
      end

      def self.traces(resource, given, tool)
        filters = [ "service_name = #{quoted(resource.name)}", "kind = 'span'" ]
        filters << "strpos(span_name, #{quoted(given['text'])}) > 0" if given["text"].present?
        sql = "SELECT trace_id, start_timestamp, span_name, duration, otel_status_code, is_exception FROM records WHERE #{filters.join(' AND ')} " \
              "ORDER BY (otel_status_code = 'ERROR' OR is_exception) DESC, duration DESC LIMIT #{Answers.limit(given, TRACE_LIMIT)}"
        call(sql, given, tool) { |rows, result| traces_result(resource, rows, result) }
      end

      def self.errors(resource, given, tool)
        filters = [ "service_name = #{quoted(resource.name)}", "is_exception" ]
        filters << "strpos(exception_message, #{quoted(given['text'])}) > 0" if given["text"].present?
        sql = "SELECT exception_type, max(exception_message) AS example, count(*) AS occurrences, min(start_timestamp) AS first_seen, " \
              "max(start_timestamp) AS last_seen FROM records WHERE #{filters.join(' AND ')} GROUP BY exception_type " \
              "ORDER BY last_seen DESC LIMIT #{Answers.limit(given, ERROR_LIMIT)}"
        call(sql, given, tool) { |rows, result| errors_result(resource, rows, result) }
      end

      def self.metrics(resource, given, tool)
        names = Array(given["metrics"]).map(&:to_s).uniq
        started, ended = Answers.range(given)
        step = [ ((ended - started) / POINTS).ceil, MIN_STEP ].max
        sql = "#{metrics_sql(names, [ resource.name ], step)} ORDER BY bucket LIMIT #{(POINTS + 2) * names.size}"
        call(sql, given, tool) { |rows, result| metrics_result(resource, rows, names, step, started, ended, result) }
      end

      # Every metric asked, per bucket of step seconds and per service, in one query, each row naming its metric. Counts
      # per bucket become counts per minute.
      def self.metrics_sql(names, services, step)
        listed = services.map { |name| quoted(name) }.join(", ")
        names.map do |name|
          table, at, value, condition = METRICS_SQL.fetch(name)
          value = "#{value} / #{step / 60.0}" if COUNTED.include?(name)
          "SELECT time_bucket(interval '#{step} seconds', #{at}) AS bucket, service_name, #{quoted(name)} AS metric, #{value} AS value " \
            "FROM #{table} WHERE service_name IN (#{listed}) AND #{condition} GROUP BY bucket, service_name"
        end.join(" UNION ALL ")
      end

      def self.call(sql, given, tool)
        arguments = { "query" => sql, **times(given) }
        Route.new(tool_name: QUERY_RUN, arguments: Answers.known!(tool, arguments, NAME),
                  present: ->(result) { Answers.read(result, PROVIDER_KEY) { |body| (found = rows(body)).any? && yield(found, result) } })
      end

      # query_run takes ISO 8601 times only. Minutes alone are sent rounded to the whole minute, so a retry within the
      # minute reads the same and an approved call matches it.
      def self.times(given)
        started, ended = Answers.range(given)
        if Answers.minutes(given)
          ended = Time.zone.at((ended.to_i / 60.0).ceil * 60)
          started = ended - Answers.minutes(given).minutes
        end
        { "min_timestamp" => started.utc.iso8601, "max_timestamp" => ended.utc.iso8601 }
      end

      # Rows as objects. The skill says query_run answers JSON rows, and Logfire's query API answers rows under rows or
      # columns of values, so each of those is read and anything else reaches the agent as it came.
      def self.rows(body)
        list = body.is_a?(Array) ? body : body["rows"]
        return list.select { |row| row.is_a?(Hash) } if list.is_a?(Array)

        columns = Array(body["columns"]).select { |column| column.is_a?(Hash) && column["name"] && column["values"].is_a?(Array) }
        return [] if columns.empty?

        Array.new(columns.map { |column| column["values"].size }.max) { |index| columns.to_h { |column| [ column["name"], column["values"][index] ] } }
      end

      def self.logs_result(resource, rows, limit, result)
        lines = rows.filter_map do |row|
          at = Answers.time_of(row["start_timestamp"])
          Telemetry::LogLine.new(at: at, source: row["level"].presence || resource.name, text: row["message"] || row["span_name"]) if at
        end
        return if lines.empty?

        Answers.presented(result, Telemetry.logs_text(lines.sort_by(&:at).reverse, asked: "#{resource.name} in Logfire", limit: limit))
      end

      def self.traces_result(resource, rows, result)
        shown = rows.filter_map do |row|
          next if row["trace_id"].blank?

          failed = row["otel_status_code"] == "ERROR" || row["is_exception"] == true
          [ Answers.time_of(row["start_timestamp"])&.iso8601, "trace #{row['trace_id']}", row["span_name"],
            "#{(row['duration'].to_f * 1000).round(1)} ms", ("failed" if failed) ].compact.join(", ")
        end
        return if shown.empty?

        Answers.presented(result, "#{shown.size} spans of #{resource.name} in Logfire, failed first, then slowest. query_run with " \
                                  "WHERE trace_id = '<id>' shows every span of one trace.\n#{shown.join("\n")}")
      end

      def self.errors_result(resource, rows, result)
        shown = rows.map do |row|
          "#{row['exception_type'].presence || 'Exception'}: #{row['occurrences'].to_i} times, first #{row['first_seen']}, last #{row['last_seen']}. " \
            "#{row['example'].to_s.truncate(300)}"
        end
        Answers.presented(result, "#{shown.size} kinds of exception in #{resource.name} in Logfire, latest first.\n#{shown.join("\n")}")
      end

      def self.metrics_result(resource, rows, names, step, started, ended, result)
        link = Answers.linked(result)
        charts = names.map do |name|
          points = rows.select { |row| row["metric"] == name }.filter_map do |row|
            at = Answers.time_of(row["bucket"])
            value = Float(row["value"], exception: false)
            [ at, value ] if at && value
          end
          Telemetry::Chart.new(title: "#{METRIC_TITLES.fetch(name)} of #{resource.name}", unit: METRIC_UNITS.fetch(name),
                               series: [ Telemetry::Series.new(label: resource.name, points: points.sort_by(&:first)) ], from: started, to: ended, link: link)
        end
        Answers.presented(result, "#{Telemetry.charts_text(charts)}\nRead from Logfire in buckets of #{step / 60} minutes.", charts: charts)
      end

      # A string literal in Logfire's SQL, quotes doubled.
      def self.quoted(text) = "'#{text.to_s.gsub("'", "''")}'"

      private_class_method :logs, :traces, :errors, :metrics, :call, :times, :logs_result, :traces_result, :errors_result, :metrics_result
    end
  end
end
