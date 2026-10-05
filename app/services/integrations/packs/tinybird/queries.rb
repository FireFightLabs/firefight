module Integrations
  module Packs
    class Tinybird < NativePack
      # The SQL Firefight writes on Tinybird's service data sources, the tables Tinybird keeps about a workspace's own use
      # (tinybird.co/docs/forward/monitoring/service-datasources). Every value is a quoted literal, so a person's or
      # Halon's words never become SQL. Minutes alone stay relative to now(), so the same request reads the same each
      # time and an approved call matches its retry. A start or end is an absolute time in UTC.
      module Queries
        # Every request to an API endpoint, and to the Query API under the name query_api, kept three months.
        PIPE_STATS = "tinybird.pipe_stats_rt".freeze
        # Every operation on a data source: appends, replaces, deletes, populates, copies and their results.
        OPS_LOG = "tinybird.datasources_ops_log".freeze
        # The last 30 days of requests to published endpoints that failed.
        ENDPOINT_ERRORS = "tinybird.endpoint_errors".freeze
        # Every job: copies, deletes, deployments, imports, populates, syncs and sinks.
        JOBS_LOG = "tinybird.jobs_log".freeze
        QUERY_API = "query_api".freeze
        JOB_DEPLOYMENT = "deployment".freeze
        JOB_TYPES = %w[copy delete deployment dynamodb_sync gcs_sync import populate s3_sync sink].freeze
        JOB_STATUSES = %w[waiting working done error cancelled].freeze
        JOB_RUNNING = %w[waiting working].freeze
        RESULT_ERROR = "error".freeze
        RESULT_OK = "ok".freeze
        TEXT_LIMIT = 500
        SHOWN = 300
        ROWS = 10_000
        POINTS = 60
        BUCKETS = [ 1, 5, 15, 60, 360, 1440 ].freeze
        HEALTH_MINUTES = 60

        module_function

        # A string as a ClickHouse literal, with the backslash and quote that could end it escaped.
        def literal(value)
          text = value.to_s
          raise NativePack::Error, "Keep each filter under #{TEXT_LIMIT} characters." if text.length > TEXT_LIMIT

          "'#{text.gsub(/[\\']/) { |character| "\\#{character}" }}'"
        end

        def time_literal(time) = "toDateTime(#{literal(time.utc.strftime('%Y-%m-%d %H:%M:%S'))}, 'UTC')"

        # The time asked for as SQL, from and to.
        def range_sql(arguments)
          ended = Telemetry.parse_time(arguments["end"])
          started = Telemetry.parse_time(arguments["start"])
          minutes = Capabilities::Answers.minutes(arguments.except("start", "end"))
          to = ended ? time_literal(ended) : "now()"
          from = if started
            time_literal([ started, (ended || Time.current) - Capabilities::MAX_MINUTES.minutes ].max)
          else
            "#{to} - INTERVAL #{minutes} MINUTE"
          end
          [ from, to ]
        end

        def window(column, arguments)
          from, to = range_sql(arguments)
          "#{column} >= #{from} AND #{column} <= #{to}"
        end

        # text and exclude as plain text, whatever the case, and regex as RE2 through match, which cannot run away.
        def filters(column, arguments)
          conditions = []
          conditions << "positionCaseInsensitive(#{column}, #{literal(arguments['text'])}) > 0" if arguments["text"].present?
          conditions << "match(#{column}, #{literal(arguments['regex'])})" if arguments["regex"].present?
          conditions << "positionCaseInsensitive(#{column}, #{literal(arguments['exclude'])}) = 0" if arguments["exclude"].present?
          conditions.map { |condition| " AND #{condition}" }.join
        end

        # One resource by its id or its name, which Tinybird keeps beside each other in every service data source.
        def named(id_column, name_column, reference)
          return "" if reference.blank?

          " AND (#{id_column} = #{literal(reference)} OR #{name_column} = #{literal(reference)})"
        end

        def requests(arguments, limit)
          text = "concat(url, ' ', ifNull(error_message, ''))"
          "SELECT start_datetime AS at, pipe_name, status_code, round(duration * 1000, 1) AS ms, read_rows, result_rows, error, " \
            "left(ifNull(error_message, ''), #{SHOWN}) AS message, left(url, #{SHOWN}) AS address, token_name FROM #{PIPE_STATS} " \
            "WHERE #{window('start_datetime', arguments)}#{named('pipe_id', 'pipe_name', arguments['endpoint'])}" \
            "#{' AND error = 1' if arguments['failed_only']}#{filters(text, arguments)} ORDER BY start_datetime DESC LIMIT #{limit}"
        end

        def operations(arguments, limit)
          text = "concat(event_type, ' ', ifNull(error, ''), ' ', pipe_name)"
          event = arguments["event_type"].present? ? " AND event_type = #{literal(arguments['event_type'])}" : ""
          "SELECT timestamp AS at, datasource_name, event_type, result, round(elapsed_time, 3) AS seconds, rows, rows_quarantine, " \
            "pipe_name, left(ifNull(error, ''), #{SHOWN}) AS message FROM #{OPS_LOG} WHERE #{window('timestamp', arguments)}" \
            "#{named('datasource_id', 'datasource_name', arguments['datasource'])}#{event}" \
            "#{" AND result = #{literal(RESULT_ERROR)}" if arguments['failed_only']}#{filters(text, arguments)} " \
            "ORDER BY timestamp DESC LIMIT #{limit}"
        end

        # Failed endpoint requests, failed data source operations and failed jobs, grouped by what failed and why.
        def errors(arguments, limit)
          name = arguments["name"]
          text = arguments.slice("text")
          endpoint = "SELECT 'endpoint' AS source, pipe_name AS name, concat('HTTP ', toString(ifNull(status_code, 0)), ', ', " \
                     "left(ifNull(error, ''), #{SHOWN})) AS message, count() AS times, min(start_datetime) AS first_seen, " \
                     "max(start_datetime) AS last_seen FROM #{ENDPOINT_ERRORS} WHERE #{window('start_datetime', arguments)}" \
                     "#{named('pipe_id', 'pipe_name', name)}#{filters("ifNull(error, '')", text)} GROUP BY name, message"
          operation = "SELECT 'data source' AS source, datasource_name AS name, concat(event_type, ', ', left(ifNull(error, ''), #{SHOWN})) AS message, " \
                      "count() AS times, min(timestamp) AS first_seen, max(timestamp) AS last_seen FROM #{OPS_LOG} " \
                      "WHERE #{window('timestamp', arguments)} AND result = #{literal(RESULT_ERROR)}" \
                      "#{named('datasource_id', 'datasource_name', name)}#{filters("ifNull(error, '')", text)} GROUP BY name, message"
          job = "SELECT 'job' AS source, if(pipe_name = '', job_type, concat(job_type, ' ', pipe_name)) AS name, " \
                "left(ifNull(error, ''), #{SHOWN}) AS message, count() AS times, min(created_at) AS first_seen, max(created_at) AS last_seen " \
                "FROM #{JOBS_LOG} WHERE #{window('created_at', arguments)} AND status = #{literal(RESULT_ERROR)}" \
                "#{named('pipe_id', 'pipe_name', name)}#{filters("ifNull(error, '')", text)} GROUP BY name, message"
          "SELECT * FROM (#{endpoint} UNION ALL #{operation} UNION ALL #{job}) ORDER BY times DESC LIMIT #{limit}"
        end

        # Requests per bucket, for one endpoint or for every request the workspace answered.
        def metrics(arguments, minutes)
          "SELECT toStartOfInterval(start_datetime, INTERVAL #{minutes} MINUTE) AS at, count() AS requests, countIf(error = 1) AS errors, " \
            "countIf(status_code >= 400 AND status_code < 500) AS http_4xx, countIf(status_code >= 500) AS http_5xx, " \
            "avg(cpu_time) AS cpu, avg(duration) AS latency_avg, quantile(0.95)(duration) AS latency_p95 FROM #{PIPE_STATS} " \
            "WHERE #{window('start_datetime', arguments)}#{named('pipe_id', 'pipe_name', arguments['endpoint'])} " \
            "GROUP BY at ORDER BY at LIMIT #{ROWS}"
        end

        # Requests and failures per hour and endpoint over a baseline's window.
        def hourly(from, to)
          "SELECT toStartOfHour(start_datetime) AS at, pipe_id, count() AS requests, countIf(error = 1) AS errors FROM #{PIPE_STATS} " \
            "WHERE start_datetime >= #{time_literal(from)} AND start_datetime < #{time_literal(to)} GROUP BY at, pipe_id ORDER BY at LIMIT #{ROWS * 10}"
        end

        def jobs(arguments, days, limit)
          type = arguments["job_type"].present? ? " AND job_type = #{literal(arguments['job_type'])}" : ""
          status = arguments["status"].present? ? " AND status = #{literal(arguments['status'])}" : ""
          "SELECT created_at, job_id, job_type, pipe_name, status, started_at, updated_at, left(ifNull(error, ''), #{SHOWN}) AS message, " \
            "left(toString(job_metadata), #{SHOWN}) AS metadata FROM #{JOBS_LOG} WHERE created_at >= now() - INTERVAL #{days} DAY#{type}#{status} " \
            "ORDER BY created_at DESC LIMIT #{limit}"
        end

        # How each endpoint answered in the last hour, by its id.
        def endpoint_health
          "SELECT pipe_id, any(pipe_name) AS name, count() AS requests, countIf(error = 1) AS failed, countIf(status_code >= 500) AS server_errors, " \
            "quantile(0.95)(duration) AS p95 FROM #{PIPE_STATS} WHERE start_datetime >= now() - INTERVAL #{HEALTH_MINUTES} MINUTE GROUP BY pipe_id"
        end

        # How each data source's operations went in the last hour, by its id, with the latest error.
        def datasource_health
          "SELECT datasource_id, any(datasource_name) AS name, countIf(result = #{literal(RESULT_OK)}) AS ok, " \
            "countIf(result = #{literal(RESULT_ERROR)}) AS failed, argMaxIf(left(ifNull(error, ''), #{SHOWN}), timestamp, result = #{literal(RESULT_ERROR)}) AS last_error " \
            "FROM #{OPS_LOG} WHERE timestamp >= now() - INTERVAL #{HEALTH_MINUTES} MINUTE GROUP BY datasource_id"
        end

        # The newest deployments, to tell one in progress.
        def deployments(limit)
          "SELECT created_at, job_id, status, left(ifNull(error, ''), #{SHOWN}) AS message FROM #{JOBS_LOG} " \
            "WHERE job_type = #{literal(JOB_DEPLOYMENT)} AND created_at >= now() - INTERVAL 30 DAY ORDER BY created_at DESC LIMIT #{limit}"
        end

        def bucket_minutes(started, ended)
          wanted = (ended - started) / 60.0 / POINTS
          BUCKETS.find { |minutes| minutes >= wanted } || BUCKETS.last
        end
      end
    end
  end
end
