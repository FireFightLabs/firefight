module Integrations
  module Packs
    # One Tinybird workspace per environment, read with a token the workspace creates in Tinybird: its data sources and
    # API endpoints, read-only SQL, and what Tinybird records about its own use in its service data sources (every
    # endpoint request, every data source operation, every job and every failed request). Every tool reads. Tinybird's
    # own MCP server takes its token in the address it is reached at, so Firefight reads Tinybird's API instead and keeps
    # the token among the credentials. Tinybird documents no rollback, restart or scale, so none is offered.
    class Tinybird < NativePack
      # The environment row's credentials, which only this pack reads.
      TOKEN = "token".freeze

      PROVIDER = "Tinybird".freeze
      PROVIDER_KEY = "tinybird".freeze
      # What each resource is, kept in its details on the map so a capability knows which tool reads it.
      TYPE_WORKSPACE = "Workspace".freeze
      TYPE_DATASOURCE = "Data source".freeze
      TYPE_ENDPOINT = "API endpoint".freeze
      # Firefight's words for how each stands, from the last hour of its service data sources.
      RUNNING = "running".freeze
      DEPLOYING = "deploying".freeze
      HEALTHY = "healthy".freeze
      DEGRADED = "degraded".freeze
      FAILED = "failed".freeze
      QUIET = "ready".freeze

      LOG_LIMIT = 200
      ROW_LIMIT = 100
      MAX_ROWS = 500
      ERROR_LIMIT = 50
      JOB_LIMIT = 20
      JOB_DAYS = 7
      MAX_JOB_DAYS = 30
      CELL_LIMIT = 300
      METRICS = %w[requests errors http_4xx http_5xx cpu_time latency].freeze
      DEFAULT_METRICS = %w[requests errors latency].freeze
      # Each metric's column in the metrics query, its title, unit and how a bucket's value becomes that unit.
      Metric = Data.define(:columns, :title, :unit, :convert)
      PER_MINUTE = "per minute".freeze
      MILLISECONDS = "ms".freeze
      COUNTED = ->(value, minutes) { value / minutes }
      SECONDS = ->(value, _minutes) { value * 1000 }
      METRICS_READ = {
        "requests" => Metric.new(columns: { "requests" => nil }, title: "Requests", unit: PER_MINUTE, convert: COUNTED),
        "errors" => Metric.new(columns: { "errors" => nil }, title: "Failed requests", unit: PER_MINUTE, convert: COUNTED),
        "http_4xx" => Metric.new(columns: { "http_4xx" => nil }, title: "4xx responses", unit: PER_MINUTE, convert: COUNTED),
        "http_5xx" => Metric.new(columns: { "http_5xx" => nil }, title: "5xx responses", unit: PER_MINUTE, convert: COUNTED),
        "cpu_time" => Metric.new(columns: { "cpu" => nil }, title: "CPU time per request, average", unit: MILLISECONDS, convert: SECONDS),
        "latency" => Metric.new(columns: { "latency_avg" => "average", "latency_p95" => "95th percentile" }, title: "Latency",
                                unit: MILLISECONDS, convert: SECONDS)
      }.freeze
      HEALTH_QUERY = "SELECT count() FROM #{Queries::JOBS_LOG} WHERE created_at >= now() - INTERVAL 1 MINUTE".freeze
      READ_ONLY = /\A\s*(SELECT|WITH|DESCRIBE|DESC|SHOW|EXPLAIN)\b/i
      FORMAT_CLAUSE = /\bFORMAT\s+\w+\s*\z/i

      RANGE = Capabilities::RANGE
      ENDPOINT = { "type" => "string", "description" => "The API endpoint, by its name or id (optional, every request the workspace answered)" }.freeze
      DATASOURCE = { "type" => "string", "description" => "The data source, by its name or id (optional, every data source)" }.freeze
      FILTERS = {
        "text" => { "type" => "string", "description" => "Only rows containing this text, whatever the case (optional)" },
        "regex" => { "type" => "string", "description" => "Only rows matching this RE2 regular expression (optional)" },
        "exclude" => { "type" => "string", "description" => "Leave out rows containing this text (optional)" }
      }.freeze

      tool :describe_resource,
           description: "How one Tinybird resource stands. Without a name, the workspace: its region, how many data sources and " \
                        "endpoints it has, the endpoints that failed in the last hour, the data sources whose operations failed " \
                        "and its latest deployments. With a data source's name, its engine, rows, size, quarantined rows and " \
                        "the pipes that read it. With an endpoint's name, its nodes, its parameters and how it answered in the last hour",
           params_schema: {
             "type" => "object",
             "properties" => { "name" => { "type" => "string", "description" => "A data source or API endpoint, by its name or id (optional, the workspace)" } }
           },
           read_only: true

      tool :list_datasources,
           description: "Every data source the token reads, with its engine, rows, size and the pipes that read it",
           params_schema: { "type" => "object", "properties" => {} },
           read_only: true

      tool :list_endpoints,
           description: "Every pipe published as an API endpoint, with its description, the data sources it reads and the parameters " \
                        "call_endpoint takes for it",
           params_schema: { "type" => "object", "properties" => {} },
           read_only: true

      tool :run_query,
           description: "Run one read-only SQL query through Tinybird's Query API, on the workspace's data sources and pipes, and on " \
                        "its service data sources such as tinybird.pipe_stats_rt, tinybird.datasources_ops_log, tinybird.endpoint_errors " \
                        "and tinybird.jobs_log. Tinybird's SQL is ClickHouse's. Leave out FORMAT, since Firefight asks for JSON itself",
           params_schema: {
             "type" => "object",
             "properties" => {
               "sql" => { "type" => "string", "description" => "One SELECT, WITH, DESCRIBE, SHOW or EXPLAIN statement" },
               "limit" => { "type" => "integer", "description" => "At most this many rows shown (optional, #{ROW_LIMIT}, at most #{MAX_ROWS})" }
             },
             "required" => [ "sql" ]
           },
           read_only: true

      tool :call_endpoint,
           description: "Call a published API endpoint with its own parameters and read what it answers, as its users would. " \
                        "list_endpoints names each endpoint's parameters. A call counts toward the endpoint's rate limits",
           params_schema: {
             "type" => "object",
             "properties" => {
               "endpoint" => { "type" => "string", "description" => "The endpoint, by its name" },
               "params" => { "type" => "object", "description" => "The endpoint's own parameters, by name (optional)" },
               "limit" => { "type" => "integer", "description" => "At most this many rows shown (optional, #{ROW_LIMIT}, at most #{MAX_ROWS})" }
             },
             "required" => [ "endpoint" ]
           },
           read_only: true

      tool :endpoint_requests,
           description: "Requests to the workspace's API endpoints and Query API, newest first, at most #{LOG_LIMIT}, from " \
                        "tinybird.pipe_stats_rt: when, which endpoint, the status, how long it took, rows read and returned, the " \
                        "token's name and the error when it failed",
           params_schema: {
             "type" => "object",
             "properties" => {
               "endpoint" => ENDPOINT, **FILTERS,
               "failed_only" => { "type" => "boolean", "description" => "Only requests that failed (optional)" },
               "limit" => { "type" => "integer", "description" => "At most this many requests (optional, #{LOG_LIMIT})" },
               **RANGE
             }
           },
           read_only: true

      tool :datasource_operations,
           description: "Operations on the workspace's data sources, newest first, at most #{LOG_LIMIT}, from " \
                        "tinybird.datasources_ops_log: appends, replaces, deletes, populates and copies, with their result, rows, " \
                        "quarantined rows, the pipe that wrote and the error when one failed",
           params_schema: {
             "type" => "object",
             "properties" => {
               "datasource" => DATASOURCE, **FILTERS,
               "event_type" => { "type" => "string", "description" => "Only operations of this kind, such as append, replace or populateview (optional)" },
               "failed_only" => { "type" => "boolean", "description" => "Only operations that failed (optional)" },
               "limit" => { "type" => "integer", "description" => "At most this many operations (optional, #{LOG_LIMIT})" },
               **RANGE
             }
           },
           read_only: true

      tool :list_errors,
           description: "What failed in the workspace, grouped by what failed and why, most frequent first: endpoint requests from " \
                        "tinybird.endpoint_errors, data source operations and jobs. Narrow it to one data source or endpoint by name",
           params_schema: {
             "type" => "object",
             "properties" => {
               "name" => { "type" => "string", "description" => "A data source or API endpoint, by its name or id (optional, the whole workspace)" },
               "text" => { "type" => "string", "description" => "Only errors containing this text (optional)" },
               "limit" => { "type" => "integer", "description" => "At most this many groups (optional, #{ERROR_LIMIT})" },
               **RANGE
             }
           },
           read_only: true

      tool :endpoint_metrics,
           description: "Requests, failures, 4xx and 5xx responses, CPU time and latency over time for one API endpoint, or for every " \
                        "request the workspace answered, from tinybird.pipe_stats_rt. The person sees each metric as a chart",
           params_schema: {
             "type" => "object",
             "properties" => {
               "endpoint" => ENDPOINT,
               "metrics" => { "type" => "array", "items" => { "type" => "string", "enum" => METRICS },
                              "description" => "Which metrics (optional, #{DEFAULT_METRICS.join(', ')})" },
               **RANGE
             }
           },
           read_only: true

      tool :jobs,
           description: "The workspace's jobs, newest first, from tinybird.jobs_log: deployments, copies, populates, imports, syncs and " \
                        "sinks, with their status, when each started and ended, and the error when one failed",
           params_schema: {
             "type" => "object",
             "properties" => {
               "job_type" => { "type" => "string", "enum" => Queries::JOB_TYPES, "description" => "Only jobs of this kind (optional)" },
               "status" => { "type" => "string", "enum" => Queries::JOB_STATUSES, "description" => "Only jobs in this status (optional)" },
               "days" => { "type" => "integer", "description" => "How many days back to look (optional, #{JOB_DAYS}, at most #{MAX_JOB_DAYS})" },
               "limit" => { "type" => "integer", "description" => "At most this many jobs (optional, #{JOB_LIMIT})" }
             }
           },
           read_only: true

      def self.credential_fields
        [
          CredentialField.new(key: TOKEN, label: "Token", secret: true, placeholder: "p.eyJ...",
                              hint: "A workspace token with the WORKSPACE:READ_ALL scope, which reads data sources, pipes and Tinybird's " \
                                    "service data sources, made with tb token create static firefight --scope WORKSPACE:READ_ALL. " \
                                    "The workspace admin token works too.")
        ]
      end

      # Reads the workspace and one service data source with the token in the region chosen, so the form says when the
      # token is wrong, belongs to another region or cannot read what Firefight reads.
      def self.credential_refusal(values, region: nil, fields: {})
        token = values[TOKEN].to_s.strip
        return "Paste a token." if token.empty?

        api = TinybirdApi.new(token, region: region&.key)
        api.workspace
        api.query(HEALTH_QUERY)
        nil
      rescue TinybirdApi::Refused => error
        Sentence.join("Tinybird refused this token in #{region&.label || 'its default region'}", error,
                      after: "Check the region the workspace is in, and that the token has the WORKSPACE:READ_ALL scope")
      rescue TinybirdApi::Error => error
        Sentence.join("Tinybird could not be read with this token", error)
      end

      def self.store_credentials!(environment_row, values)
        environment_row.store_credential!(TOKEN, values[TOKEN].to_s.strip)
      end

      def describe_resource(environment_row:, arguments:)
        name = arguments["name"].to_s.strip
        return workspace_status(environment_row) if name.empty?

        api = api(environment_row)
        datasource = Named.find(read { api.datasources }, name, id: "id", name: "name", provider: PROVIDER)
        return datasource_status(environment_row, datasource) if datasource

        pipe = Named.find(read { api.pipes }, name, id: "id", name: "name", provider: PROVIDER)
        fail! "#{PROVIDER} has no data source or pipe called #{name} in this workspace. list_datasources and list_endpoints name them." unless pipe

        endpoint_status(environment_row, pipe)
      end

      def list_datasources(environment_row:, arguments:)
        datasources = read { api(environment_row).datasources }
        return Telemetry.result("The token reads no data sources in this workspace.", link: workspace_link(environment_row)) if datasources.empty?

        lines = datasources.map { |datasource| datasource_line(datasource) }
        Telemetry.result("#{datasources.size} data sources.\n#{lines.join("\n")}", link: workspace_link(environment_row))
      end

      def list_endpoints(environment_row:, arguments:)
        endpoints = read { api(environment_row).pipes }.select { |pipe| endpoint?(pipe) }
        return Telemetry.result("No pipe in this workspace is published as an API endpoint.", link: workspace_link(environment_row)) if endpoints.empty?

        lines = endpoints.map do |pipe|
          params = parameters_of(pipe)
          [ "#{pipe['name']} (id #{pipe['id']})", pipe["description"].presence&.squish&.truncate(CELL_LIMIT),
            "reads #{dependencies_of(pipe).join(', ').presence || 'nothing Tinybird named'}",
            "parameters #{params.presence&.join(', ') || 'none'}" ].compact.join(", ")
        end
        Telemetry.result("#{endpoints.size} API endpoints.\n#{lines.join("\n")}", link: workspace_link(environment_row))
      end

      def run_query(environment_row:, arguments:)
        sql = arguments["sql"].to_s.strip.sub(/;\s*\z/, "")
        fail! "Give the SQL to run." if sql.empty?
        fail! "Only a SELECT, WITH, DESCRIBE, SHOW or EXPLAIN statement runs here." unless sql.match?(READ_ONLY)
        fail! "Leave out FORMAT. Firefight asks Tinybird for JSON itself." if sql.match?(FORMAT_CLAUSE)

        answer = query(api(environment_row), sql)
        Telemetry.result(rows_text(answer, Capabilities::Answers.limit(arguments, MAX_ROWS, default: ROW_LIMIT)), link: workspace_link(environment_row))
      end

      def call_endpoint(environment_row:, arguments:)
        endpoint = arguments["endpoint"].to_s.strip
        fail! "Name the endpoint to call." if endpoint.empty?
        params = arguments["params"].is_a?(Hash) ? arguments["params"] : {}

        answer = read { api(environment_row).call_endpoint(endpoint, params) }
        Telemetry.result(rows_text(answer, Capabilities::Answers.limit(arguments, MAX_ROWS, default: ROW_LIMIT)), link: workspace_link(environment_row))
      end

      def endpoint_requests(environment_row:, arguments:)
        limit = Capabilities::Answers.limit(arguments, LOG_LIMIT)
        rows = data_of(query(api(environment_row), Queries.requests(arguments, limit)))
        lines = rows.filter_map do |row|
          at = Telemetry.parse_time(row["at"])
          failed = row["error"].to_i == 1
          text = [ "HTTP #{row['status_code']}", "#{row['ms']} ms", "#{row['read_rows']} rows read", "#{row['result_rows']} returned",
                   ("token #{row['token_name']}" if row["token_name"].present?), ("failed: #{row['message']}" if failed), row["address"] ].compact.join(", ")
          at && Telemetry::LogLine.new(at: at, source: row["pipe_name"].to_s, text: text)
        end
        asked = arguments["endpoint"].present? ? "requests to #{arguments['endpoint']}" : "requests to the workspace"
        Telemetry.result(Telemetry.logs_text(lines, asked: asked, limit: limit), link: workspace_link(environment_row))
      end

      def datasource_operations(environment_row:, arguments:)
        limit = Capabilities::Answers.limit(arguments, LOG_LIMIT)
        rows = data_of(query(api(environment_row), Queries.operations(arguments, limit)))
        lines = rows.filter_map do |row|
          at = Telemetry.parse_time(row["at"])
          text = [ row["event_type"], row["result"], "#{row['seconds']} s", ("#{row['rows']} rows" unless row["rows"].nil?),
                   ("#{row['rows_quarantine']} quarantined" if row["rows_quarantine"].to_i.positive?),
                   ("by pipe #{row['pipe_name']}" if row["pipe_name"].present?), row["message"].presence ].compact.join(", ")
          at && Telemetry::LogLine.new(at: at, source: row["datasource_name"].to_s, text: text)
        end
        asked = arguments["datasource"].present? ? "operations on #{arguments['datasource']}" : "operations on the workspace's data sources"
        Telemetry.result(Telemetry.logs_text(lines, asked: asked, limit: limit), link: workspace_link(environment_row))
      end

      def list_errors(environment_row:, arguments:)
        rows = data_of(query(api(environment_row), Queries.errors(arguments, Capabilities::Answers.limit(arguments, ERROR_LIMIT))))
        about = arguments["name"].present? ? arguments["name"].to_s.strip : "the workspace"
        return Telemetry.result("Nothing failed for #{about} in that range.", link: workspace_link(environment_row)) if rows.empty?

        lines = rows.map do |row|
          Sentence.all("#{row['source']} #{row['name']}: #{row['times']} times, first #{row['first_seen']}, last #{row['last_seen']}", row["message"].to_s.squish)
        end
        Telemetry.result("What failed for #{about}, by what and why, most frequent first.\n#{lines.join("\n")}", link: workspace_link(environment_row))
      end

      def endpoint_metrics(environment_row:, arguments:)
        names = Array(arguments["metrics"]).map(&:to_s).uniq.presence || DEFAULT_METRICS
        unknown = names - METRICS
        fail! "#{PROVIDER} keeps #{METRICS.join(', ')} for endpoints, not #{unknown.join(', ')}." if unknown.any?

        started, ended = Capabilities::Answers.range(arguments)
        minutes = Queries.bucket_minutes(started, ended)
        rows = data_of(query(api(environment_row), Queries.metrics(arguments, minutes)))
        subject = arguments["endpoint"].presence || "the workspace"
        charts = names.map do |name|
          metric = METRICS_READ.fetch(name)
          series = metric.columns.map do |column, label|
            points = rows.filter_map do |row|
              at = Telemetry.parse_time(row["at"])
              [ at, metric.convert.call(row[column].to_f, minutes) ] if at && !row[column].nil?
            end
            Telemetry::Series.new(label: label || subject, points: points)
          end
          Telemetry::Chart.new(title: "#{metric.title} of #{subject}", unit: metric.unit, series: series, from: started, to: ended)
        end
        text = "#{Telemetry.charts_text(charts)}\nRead every #{minutes} minutes. A bucket with no requests has no point, which means no traffic, not zero latency."
        Telemetry.result(text, link: workspace_link(environment_row), charts: charts)
      end

      def jobs(environment_row:, arguments:)
        days = arguments["days"].to_i.positive? ? [ arguments["days"].to_i, MAX_JOB_DAYS ].min : JOB_DAYS
        fail! "job_type is one of #{Queries::JOB_TYPES.join(', ')}." if arguments["job_type"].present? && !Queries::JOB_TYPES.include?(arguments["job_type"])
        fail! "status is one of #{Queries::JOB_STATUSES.join(', ')}." if arguments["status"].present? && !Queries::JOB_STATUSES.include?(arguments["status"])

        rows = data_of(query(api(environment_row), Queries.jobs(arguments, days, Capabilities::Answers.limit(arguments, JOB_LIMIT))))
        what = arguments["job_type"].present? ? "#{arguments['job_type']} jobs" : "jobs"
        link = jobs_link(environment_row)
        return Telemetry.result("No #{what} in the last #{days} days.", link: link) if rows.empty?

        lines = rows.map { |row| job_line(row) }
        Telemetry.result("Latest #{rows.size} #{what} in the last #{days} days, newest first.\n#{lines.join("\n")}", link: link)
      end

      # The workspace, its data sources and its API endpoints on the resource map, each endpoint linked to the data
      # sources it reads, and each with how it stood in the last hour. A list that cannot be read is a gap naming its kind,
      # so the sweep never takes what it did not read as gone.
      def map_of(environment_row)
        api = api(environment_row)
        workspace = read { api.workspace }
        account = workspace["id"].to_s
        page = workspace_page(environment_row, workspace["name"])
        gaps = []
        workspace_found = ResourceMap::Found.new(
          provider: PROVIDER_KEY, account: account, kind: ResourceMap::KIND_DATABASE, external_id: account, name: workspace["name"].to_s,
          status: workspace_state(api, gaps), url: page, details: { "type" => TYPE_WORKSPACE, "region" => ConnectionSettings.of(environment_row).region&.label }.compact
        )
        resources = [ workspace_found ]
        links = []
        datasources = listed(gaps, ResourceMap::KIND_DATABASE, "data sources") { api.datasources }
        operations = health(api, Queries.datasource_health, "datasource_id", gaps, "how each data source's operations went")
        by_name = {}
        Array(datasources).each do |datasource|
          found = ResourceMap::Found.new(provider: PROVIDER_KEY, account: account, kind: ResourceMap::KIND_DATABASE, external_id: datasource["id"].to_s,
                                         name: datasource["name"].to_s, status: operations && datasource_state(operations[datasource["id"].to_s]), url: page,
                                         details: { "type" => TYPE_DATASOURCE, "engine" => datasource.dig("engine", "engine") }.compact)
          by_name[found.name] = found
          resources << found
          links << ResourceMap::FoundLink.new(from: found.key, to: workspace_found.key, relation: ResourceMap::RELATION_PART_OF)
        end
        pipes = listed(gaps, ResourceMap::KIND_FUNCTION, "pipes") { api.pipes }
        requests = health(api, Queries.endpoint_health, "pipe_id", gaps, "how each endpoint answered")
        Array(pipes).select { |pipe| endpoint?(pipe) }.each do |pipe|
          found = ResourceMap::Found.new(provider: PROVIDER_KEY, account: account, kind: ResourceMap::KIND_FUNCTION, external_id: pipe["id"].to_s,
                                         name: pipe["name"].to_s, status: requests && endpoint_state(requests[pipe["id"].to_s]), url: page,
                                         details: { "type" => TYPE_ENDPOINT })
          resources << found
          links << ResourceMap::FoundLink.new(from: found.key, to: workspace_found.key, relation: ResourceMap::RELATION_PART_OF)
          dependencies_of(pipe).filter_map { |name| by_name[name] }.each do |datasource|
            links << ResourceMap::FoundLink.new(from: found.key, to: datasource.key, relation: ResourceMap::RELATION_USES)
          end
        end
        ResourceMap::Snapshot.new(resources: resources, links: links.uniq, gaps: gaps)
      end

      # What normal looks like for the workspace and each endpoint: requests and failed requests per minute, read hour
      # by hour over the window. tinybird.pipe_stats_rt records every request, so an hour with none is a reading of zero.
      def baselines_of(environment_row, resources, window)
        mine = resources.select { |resource| resource.provider == PROVIDER_KEY }
        endpoints = mine.select { |resource| resource.kind == ResourceMap::KIND_FUNCTION }
        workspaces = mine.select { |resource| resource.details.to_h["type"] == TYPE_WORKSPACE }
        return [] if endpoints.empty? && workspaces.empty?

        hours = hours_of(window)
        return [] if hours.empty?

        rows = data_of(query(api(environment_row), Queries.hourly(hours.first, hours.last + 1.hour)))
        by_pipe = rows.group_by { |row| row["pipe_id"].to_s }
        readings = endpoints.flat_map { |resource| hourly_baselines(resource, by_pipe.fetch(resource.external_id, []), hours) }
        readings + workspaces.flat_map { |resource| hourly_baselines(resource, rows, hours) }
      end

      # Reads the workspace and one service data source, so a token that lost its scope is said here before the map
      # sweep finds every status unknown.
      def check_health!(environment_row)
        api = api(environment_row)
        api.workspace
        api.query(HEALTH_QUERY)
      rescue TinybirdApi::Error => error
        fail! error.message
      end

      private

      def api(environment_row)
        @api ||= begin
          settings = ConnectionSettings.of(environment_row)
          token = settings.credential(TOKEN)
          fail! "This environment has no Tinybird token. Reconnect it on the Integrations page." if token.nil?

          TinybirdApi.new(token, region: settings.region&.key)
        end
      end

      # A read of Tinybird's API, with Tinybird's refusal in words and a rate limit passed on as one.
      def read
        yield
      rescue Integrations::RateLimited
        raise
      rescue TinybirdApi::Refused => error
        fail! Sentence.join("Tinybird refused the read", error, after: "The token needs the WORKSPACE:READ_ALL scope, or reconnect with one that has it")
      rescue TinybirdApi::Error => error
        fail! Sentence.of(error)
      end

      def query(api, sql) = read { api.query(sql) }

      def data_of(answer) = answer.is_a?(Hash) && answer["data"].is_a?(Array) ? answer["data"] : []

      # The workspace's page in Tinybird Cloud, <site>/<workspace name>, as Tinybird's CLI opens it (tb open, in the
      # tinybird package's tb/modules/open.py). Tinybird documents no page for one data source or endpoint, so a result
      # about one links to the workspace it is in.
      def workspace_page(environment_row, name)
        site = ConnectionSettings.of(environment_row).site
        site.present? && name.present? ? "#{site.chomp('/')}/#{Http.segment(name)}" : nil
      end

      def workspace_link(environment_row)
        url = workspace_page(environment_row, workspace_name(environment_row))
        url && Telemetry::Link.new(provider: PROVIDER, url: url)
      end

      # The workspace's jobs page, <site>/<workspace name>/jobs, as the CLI prints it after a job (tb/modules/job_common.py).
      def jobs_link(environment_row)
        url = workspace_page(environment_row, workspace_name(environment_row))
        url && Telemetry::Link.new(provider: PROVIDER, url: "#{url}/jobs")
      end

      # The workspace's name, for its page. A link is worth a read, and a result is still worth giving without one.
      def workspace_name(environment_row)
        return @workspace_name if defined?(@workspace_name)

        @workspace_name = api(environment_row).workspace["name"].presence
      rescue Integrations::RateLimited
        raise
      rescue TinybirdApi::Error
        @workspace_name = nil
      end

      def workspace_status(environment_row)
        api = api(environment_row)
        workspace = read { api.workspace }
        region = ConnectionSettings.of(environment_row).region&.label
        datasources = read { api.datasources }
        pipes = read { api.pipes }
        endpoints = pipes.select { |pipe| endpoint?(pipe) }
        lines = [ "Workspace #{workspace['name']} (id #{workspace['id']})#{" in #{region}" if region}, with #{datasources.size} data sources, " \
                  "#{endpoints.size} API endpoints and #{pipes.size - endpoints.size} other pipes." ]
        requests = data_of(query(api, Queries.endpoint_health))
        total = requests.sum { |row| row["requests"].to_i }
        failed = requests.select { |row| row["failed"].to_i.positive? }
        lines << "In the last #{Queries::HEALTH_MINUTES} minutes it answered #{total} requests, #{requests.sum { |row| row['failed'].to_i }} of which failed."
        failed.sort_by { |row| -row["failed"].to_i }.each do |row|
          lines << "  #{row['name']}: #{row['failed']} of #{row['requests']} requests failed, #{row['server_errors']} with a 5xx."
        end
        operations = data_of(query(api, Queries.datasource_health)).select { |row| row["failed"].to_i.positive? }
        lines << (operations.empty? ? "No data source operation failed in the last #{Queries::HEALTH_MINUTES} minutes." : "Data sources whose operations failed in the last #{Queries::HEALTH_MINUTES} minutes:")
        operations.each { |row| lines << "  #{Sentence.all("#{row['name']}: #{row['failed']} failed, #{row['ok']} succeeded", latest_error(row))}" }
        deployments = data_of(query(api, Queries.deployments(3)))
        lines << (deployments.empty? ? "No deployment in the last 30 days." : "Latest deployments, newest first:")
        deployments.each { |row| lines << "  #{row['created_at']}, job #{row['job_id']}, #{row['status']}#{", #{row['message']}" if row['message'].present?}" }
        Telemetry.result(lines.join("\n"), link: workspace_link(environment_row))
      end

      def datasource_status(environment_row, listed)
        api = api(environment_row)
        datasource = read { api.datasource(listed["name"]) }
        lines = [ datasource_line(listed.merge(datasource)) ]
        engine = datasource["engine"].to_h
        keys = { "sorting key" => engine["sorting_key"] || engine["engine_sorting_key"], "partition key" => engine["partition_key"] || engine["engine_partition_key"] }
        keys = keys.compact_blank.map { |label, value| "#{label} #{value}" }
        lines << "Its #{keys.join(', ')}." if keys.any?
        row = data_of(query(api, Queries.datasource_health)).find { |each| each["datasource_id"].to_s == listed["id"].to_s }
        lines << if row.nil?
          "No operation on it in the last #{Queries::HEALTH_MINUTES} minutes."
        else
          Sentence.all("In the last #{Queries::HEALTH_MINUTES} minutes, #{row['ok']} operations succeeded and #{row['failed']} failed",
                       (latest_error(row) if row["failed"].to_i.positive?))
        end
        Telemetry.result(lines.join("\n"), link: workspace_link(environment_row))
      end

      def endpoint_status(environment_row, listed)
        api = api(environment_row)
        pipe = read { api.pipe(listed["name"]) }.presence || listed
        published = pipe["endpoint"].presence
        node = Array(pipe["nodes"]).find { |each| each["id"] == published }
        lines = [ "#{endpoint?(pipe) ? 'API endpoint' : 'Pipe'} #{pipe['name']} (id #{pipe['id']})#{", #{pipe['description'].squish.truncate(CELL_LIMIT)}" if pipe['description'].present?}." ]
        lines << "It publishes node #{node['name']}, of #{Array(pipe['nodes']).size} nodes." if node
        lines << "It is not published as an endpoint, so it answers no requests." unless endpoint?(pipe)
        lines << "Its parameters: #{parameters_of(pipe).join(', ')}." if parameters_of(pipe).any?
        lines << "It reads #{dependencies_of(listed).join(', ')}." if dependencies_of(listed).any?
        row = data_of(query(api, Queries.endpoint_health)).find { |each| each["pipe_id"].to_s == pipe["id"].to_s }
        lines << if row.nil?
          "It answered no requests in the last #{Queries::HEALTH_MINUTES} minutes."
        else
          "In the last #{Queries::HEALTH_MINUTES} minutes it answered #{row['requests']} requests, #{row['failed']} failed, #{row['server_errors']} " \
            "with a 5xx, and 95% took under #{(row['p95'].to_f * 1000).round(1)} ms."
        end
        Telemetry.result(lines.join("\n"), link: workspace_link(environment_row))
      end

      # The latest error a data source's operations met, as a sentence, or nil when Tinybird kept no words for it.
      def latest_error(row) = row["last_error"].to_s.squish.presence&.then { |said| "Latest error: #{said}" }

      def datasource_line(datasource)
        statistics = datasource["statistics"].to_h
        engine = datasource.dig("engine", "engine")
        used_by = Array(datasource["used_by"]).filter_map { |pipe| pipe["name"] }
        [ "#{datasource['name']} (id #{datasource['id']})", ("engine #{engine}" if engine), ("#{statistics['row_count']} rows" unless statistics["row_count"].nil?),
          ("#{statistics['bytes']} bytes" unless statistics["bytes"].nil?),
          ("#{datasource['quarantine_rows']} rows in quarantine" if datasource["quarantine_rows"].to_i.positive?),
          ("read by #{used_by.join(', ')}" if used_by.any?), datasource["description"].presence&.squish&.truncate(CELL_LIMIT) ].compact.join(", ")
      end

      def job_line(row)
        [ row["created_at"], "#{row['job_type']}#{" #{row['pipe_name']}" if row['pipe_name'].present?}", row["status"], "job #{row['job_id']}",
          ("started #{row['started_at']}" if row["started_at"].present?), ("updated #{row['updated_at']}" if row["updated_at"].present?),
          row["message"].presence, ("details #{row['metadata']}" if row["metadata"].present? && row["metadata"] != "{}") ].compact.join(", ")
      end

      # A pipe is an API endpoint when it publishes a node, as the Pipes API's endpoint field says, or its type says so.
      def endpoint?(pipe) = pipe["endpoint"].present? || pipe["type"].to_s == "endpoint"

      # The data sources and pipes a pipe's nodes read, as the Pipes API's dependencies name them, less its own nodes.
      def dependencies_of(pipe)
        nodes = Array(pipe["nodes"])
        own = nodes.map { |node| node["name"] }
        nodes.flat_map { |node| Array(node["dependencies"]) }.map(&:to_s).uniq - own
      end

      # The parameters a pipe's nodes declare, each with its type and whether it is required.
      def parameters_of(pipe)
        Array(pipe["nodes"]).flat_map { |node| Array(node["params"]) }.filter_map do |param|
          next unless param.is_a?(Hash) && param["name"].present?

          "#{param['name']} (#{[ param['type'], ('required' if param['required']) ].compact.join(', ')})"
        end.uniq
      end

      # A query's rows as lines a person and Halon read, with what Tinybird read to answer it.
      def rows_text(answer, limit)
        rows = data_of(answer)
        statistics = answer.is_a?(Hash) ? answer["statistics"].to_h : {}
        cost = statistics.any? ? " Tinybird read #{statistics['rows_read']} rows, #{statistics['bytes_read']} bytes, in #{statistics['elapsed']} s." : ""
        return "No rows.#{cost}" if rows.empty?

        shown = rows.first(limit).map { |row| row.map { |column, value| "#{column}: #{value.to_s.squish.truncate(CELL_LIMIT)}" }.join(", ") }
        cut = rows.size > limit ? " Only the first #{limit} are shown, so narrow the query to see the rest." : ""
        "#{rows.size} rows.#{cost}#{cut}\n#{shown.join("\n")}"
      end

      # A list for the map, or nil with a gap naming the kind it holds when it cannot be read.
      def listed(gaps, kind, what)
        yield
      rescue Integrations::RateLimited
        raise
      rescue TinybirdApi::Error => error
        gaps << ResourceMap::Gap.new(text: Sentence.join("Tinybird's #{what} could not be read", error), kinds: [ kind ])
        nil
      end

      # The last hour of a service data source by id, or nil with a gap when it cannot be read, so every status stays
      # unknown rather than reading as quiet.
      def health(api, sql, id, gaps, what)
        api.query(sql)["data"].to_a.index_by { |row| row[id].to_s }
      rescue Integrations::RateLimited
        raise
      rescue TinybirdApi::Error => error
        gaps << ResourceMap::Gap.new(text: Sentence.join("#{what.capitalize} could not be read, so their status is not known", error), kinds: [])
        nil
      end

      def workspace_state(api, gaps)
        latest = data_of(api.query(Queries.deployments(1))).first
        latest && Queries::JOB_RUNNING.include?(latest["status"].to_s) ? DEPLOYING : RUNNING
      rescue Integrations::RateLimited
        raise
      rescue TinybirdApi::Error => error
        gaps << ResourceMap::Gap.new(text: Sentence.join("Its deployments could not be read, so whether one is in progress is not known", error), kinds: [])
        nil
      end

      # Failed when every operation in the last hour failed, degraded when some did, healthy when they all succeeded, and
      # ready when nothing ran.
      def datasource_state(row)
        return QUIET if row.nil?

        ok = row["ok"].to_i
        failed = row["failed"].to_i
        return FAILED if failed.positive? && ok.zero?

        failed.positive? ? DEGRADED : HEALTHY
      end

      # Failed when every request in the last hour failed, degraded when any answered a 5xx, healthy otherwise, and ready
      # when nothing asked. A 4xx is the caller's mistake, such as a missing parameter, so it alone degrades nothing.
      def endpoint_state(row)
        return QUIET if row.nil? || row["requests"].to_i.zero?
        return FAILED if row["failed"].to_i == row["requests"].to_i

        row["server_errors"].to_i.positive? ? DEGRADED : HEALTHY
      end

      # The whole hours inside the window, so neither end counts a part of an hour as all of one.
      def hours_of(window)
        first = window.begin.utc.beginning_of_hour
        first += 1.hour if first < window.begin
        last = window.end.utc.beginning_of_hour
        (0...((last - first) / 3600).to_i).map { |hour| first + hour.hours }
      end

      def hourly_baselines(resource, rows, hours)
        by_hour = rows.group_by { |row| Telemetry.parse_time(row["at"])&.utc&.beginning_of_hour }
        %w[requests errors].map do |name|
          metric = METRICS_READ.fetch(name)
          points = hours.map { |hour| [ hour, Array(by_hour[hour]).sum { |row| row[name].to_f } / 60.0 ] }
          ResourceMap::Baseline::Found.new(key: resource.key, metric: name, label: metric.title, unit: metric.unit, points: points)
        end
      end
    end
  end
end
