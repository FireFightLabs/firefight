module Integrations
  module Packs
    # Northflank telemetry for one project per environment: what runs there, its logs, its metrics and its builds. It
    # connects with a read-only API token the workspace creates in Northflank. Every tool only reads.
    class Northflank < NativePack
      # The environment row's credentials, which only this pack reads.
      API_TOKEN = "api_token".freeze
      PROJECT = "project".freeze

      APP_ROOT = "https://app.northflank.com".freeze
      KIND_SERVICES = "services".freeze
      KIND_ADDONS = "addons".freeze

      LOG_TYPES = %w[runtime build ingress mesh cdn backup restore].freeze
      METRICS = %w[cpu memory requests http4xxResponses http5xxResponses networkIngress networkEgress tcpConnectionsOpen diskUsage bandwidth].freeze
      DEFAULT_METRICS = %w[cpu memory requests http5xxResponses].freeze
      UNITS = { "pct" => "%", "vCPU" => "vCPU", "mb" => "MB", "kbps" => "kbps", "rps" => "requests/s", "count" => "count" }.freeze
      METRIC_TITLES = {
        "cpu" => "CPU", "memory" => "Memory", "requests" => "Requests", "http4xxResponses" => "4xx responses",
        "http5xxResponses" => "5xx responses", "networkIngress" => "Network in", "networkEgress" => "Network out",
        "tcpConnectionsOpen" => "Open TCP connections", "diskUsage" => "Disk usage", "bandwidth" => "Bandwidth"
      }.freeze
      DEFAULT_MINUTES = 60
      MAX_MINUTES = 7 * 24 * 60
      LOG_LIMIT = 200
      BUILD_LIMIT = 10

      RANGE = {
        "minutes" => { "type" => "integer", "description" => "How far back from now, in minutes (optional, #{DEFAULT_MINUTES})" },
        "start" => { "type" => "string", "description" => "Start of the range as an ISO 8601 time, instead of minutes (optional)" },
        "end" => { "type" => "string", "description" => "End of the range as an ISO 8601 time (optional, now)" }
      }.freeze
      RESOURCE = { "type" => "string", "description" => "A service or database (addon) in the project, by name or id, as list_resources shows it" }.freeze

      tool :list_resources,
           description: "The services and databases (addons) in the Northflank project for this environment, with their type and " \
                        "whether each is running, deploying or failed. Use it first to find the name to pass to the other tools",
           params_schema: { "type" => "object", "properties" => {} },
           read_only: true

      tool :search_logs,
           description: "Log lines from one service or database, newest first, at most #{LOG_LIMIT}. Filter by text or a regular " \
                        "expression, and by log type: runtime for what the app prints, build, ingress for HTTP requests reaching it",
           params_schema: {
             "type" => "object",
             "properties" => {
               "resource" => RESOURCE,
               "text" => { "type" => "string", "description" => "Only lines containing this text (optional)" },
               "regex" => { "type" => "string", "description" => "Only lines matching this regular expression (optional)" },
               "exclude" => { "type" => "string", "description" => "Leave out lines containing this text (optional)" },
               "type" => { "type" => "string", "enum" => LOG_TYPES, "description" => "Which logs (optional, runtime)" },
               "limit" => { "type" => "integer", "description" => "At most this many lines (optional, #{LOG_LIMIT})" },
               **RANGE
             },
             "required" => [ "resource" ]
           },
           read_only: true

      tool :query_metrics,
           description: "Metrics of one service or database over time: CPU, memory, requests, 4xx and 5xx responses, network, " \
                        "open TCP connections and disk. Returns min, average, max and latest per container, and the person " \
                        "sees each metric as a chart",
           params_schema: {
             "type" => "object",
             "properties" => {
               "resource" => RESOURCE,
               "metrics" => { "type" => "array", "items" => { "type" => "string", "enum" => METRICS },
                              "description" => "Which metrics (optional, #{DEFAULT_METRICS.join(', ')})" },
               **RANGE
             },
             "required" => [ "resource" ]
           },
           read_only: true

      tool :recent_builds,
           description: "The latest builds of one service, newest first, with commit, branch, when it ran and whether it succeeded. " \
                        "Use it to see what changed before something broke",
           params_schema: {
             "type" => "object",
             "properties" => {
               "resource" => RESOURCE,
               "limit" => { "type" => "integer", "description" => "At most this many builds (optional, #{BUILD_LIMIT})" }
             },
             "required" => [ "resource" ]
           },
           read_only: true

      def self.credential_fields
        [
          CredentialField.new(key: API_TOKEN, label: "API token", secret: true, placeholder: "nf-...",
                              hint: "A Northflank API token whose role can read projects and view observability, and nothing else."),
          CredentialField.new(key: PROJECT, label: "Project", secret: false, placeholder: "my-project",
                              hint: "The id of the Northflank project this environment runs in, as it appears in the project's URL.")
        ]
      end

      # Reads the project with the token, so a wrong token or project is said on the form before anything is saved.
      def self.credential_refusal(values)
        token = values[API_TOKEN].to_s.strip
        project = values[PROJECT].to_s.strip
        return "Paste an API token." if token.empty?
        return "Enter the project id." if project.empty?

        NorthflankApi.new(token).project(project)
        nil
      rescue NorthflankApi::Error => error
        "Northflank refused this token or project. #{error.message}"
      end

      def self.store_credentials!(environment_row, values)
        environment_row.store_credential!(API_TOKEN, values[API_TOKEN].to_s.strip)
        environment_row.store_credential!(PROJECT, values[PROJECT].to_s.strip)
      end

      def list_resources(environment_row:, arguments:)
        project = project_of(environment_row)
        rows = resources(environment_row).map do |resource|
          "#{resource[:name]} (#{resource[:id]}), #{resource[:type]}, #{resource[:status]}"
        end
        return Telemetry.result("Project #{project} has no services or databases.") if rows.empty?

        Telemetry.result("Project #{project}, #{rows.size} services and databases.\n#{rows.join("\n")}")
      end

      def search_logs(environment_row:, arguments:)
        resource = find_resource(environment_row, arguments["resource"])
        started, ended = Telemetry.range(arguments, default_minutes: DEFAULT_MINUTES, max_minutes: MAX_MINUTES)
        limit = arguments["limit"].to_i.positive? ? [ arguments["limit"].to_i, LOG_LIMIT ].min : LOG_LIMIT
        query = {
          "startTime" => started.utc.iso8601, "endTime" => ended.utc.iso8601, "lineLimit" => limit, "direction" => "backward",
          "type" => arguments["type"].presence_in(LOG_TYPES) || "runtime", "textIncludes" => arguments["text"].presence,
          "regexIncludes" => arguments["regex"].presence, "textNotIncludes" => arguments["exclude"].presence
        }
        lines = api(environment_row).logs(project_of(environment_row), resource[:kind], resource[:id], query).map do |line|
          Telemetry::LogLine.new(at: Telemetry.parse_time(line["ts"]) || ended, source: line["containerId"].to_s, text: line["log"])
        end
        Telemetry.result(Telemetry.logs_text(lines, asked: "#{resource[:name]} from #{started.utc.iso8601} to #{ended.utc.iso8601}"))
      end

      def query_metrics(environment_row:, arguments:)
        resource = find_resource(environment_row, arguments["resource"])
        started, ended = Telemetry.range(arguments, default_minutes: DEFAULT_MINUTES, max_minutes: MAX_MINUTES)
        asked = Array(arguments["metrics"]) & METRICS
        asked = DEFAULT_METRICS if asked.empty?
        query = { "startTime" => started.utc.iso8601, "endTime" => ended.utc.iso8601, "metricTypes" => asked }
        data = api(environment_row).metrics(project_of(environment_row), resource[:kind], resource[:id], query)
        charts = asked.filter_map { |metric| chart(environment_row, resource, metric, data[metric], started, ended) if data[metric] }
        Telemetry.result("#{resource[:name]}\n#{Telemetry.charts_text(charts)}", charts: charts)
      end

      def recent_builds(environment_row:, arguments:)
        resource = find_resource(environment_row, arguments["resource"])
        fail! "#{resource[:name]} is a database, and only services have builds." unless resource[:kind] == KIND_SERVICES

        limit = arguments["limit"].to_i.positive? ? [ arguments["limit"].to_i, BUILD_LIMIT ].min : BUILD_LIMIT
        builds = api(environment_row).builds(project_of(environment_row), resource[:id], limit: limit)
        return Telemetry.result("#{resource[:name]} has no builds.") if builds.empty?

        rows = builds.map do |build|
          outcome = build["concluded"] ? (build["success"] ? "succeeded" : "failed") : build["status"].to_s.downcase
          [ build["createdAt"], outcome, build["branch"], build["sha"].to_s.first(12), build["message"].presence ].compact.join(", ")
        end
        Telemetry.result("Latest #{rows.size} builds of #{resource[:name]}, newest first.\n#{rows.join("\n")}")
      end

      def check_health!(environment_row)
        api(environment_row).project(project_of(environment_row))
      rescue NorthflankApi::Error => error
        fail! error.message
      end

      private

      def api(environment_row)
        token = environment_row.credentials_hash[API_TOKEN]
        fail! "This environment has no Northflank token. Reconnect it on the Integrations page." if token.blank?

        NorthflankApi.new(token)
      end

      def project_of(environment_row) = environment_row.credentials_hash[PROJECT].presence || fail!("This environment has no Northflank project. Reconnect it.")

      def resources(environment_row)
        @resources ||= begin
          project = project_of(environment_row)
          services = api(environment_row).services(project).map do |service|
            status = service.dig("status", "deployment", "status") || service.dig("status", "build", "status") || "unknown"
            { kind: KIND_SERVICES, id: service["id"], name: service["name"], type: "#{service['serviceType']} service",
              status: status.to_s.downcase, app_id: service["appId"] }
          end
          addons = api(environment_row).addons(project).map do |addon|
            { kind: KIND_ADDONS, id: addon["id"], name: addon["name"], type: "#{addon.dig('spec', 'type')} database",
              status: addon["status"].to_s.downcase, app_id: addon["appId"] }
          end
          services + addons
        end
      end

      def find_resource(environment_row, asked)
        wanted = asked.to_s.strip.downcase
        fail! "Say which service or database, by name or id. list_resources shows them." if wanted.empty?

        found = resources(environment_row).find { |resource| [ resource[:id], resource[:name] ].compact.map(&:downcase).include?(wanted) }
        found || fail!("No service or database called #{asked} in this project. list_resources shows what there is.")
      end

      # The resource's page in Northflank's app. appId starts with the team, as in /team/project/service.
      def page_of(environment_row, resource)
        team = resource[:app_id].to_s.split("/").reject(&:empty?).first
        return nil if team.blank?

        segments = [ "t", team, "project", project_of(environment_row), resource[:kind], resource[:id] ].map { |part| ERB::Util.url_encode(part) }
        "#{APP_ROOT}/#{segments.join('/')}"
      end

      def chart(environment_row, resource, metric, data, started, ended)
        unit = UNITS.fetch(data.dig("metricInfo", "metricUnit").to_s, data.dig("metricInfo", "metricUnit").to_s)
        series = Array(data["values"]).map do |container|
          label = container.dig("metadata", "containerId").presence || container.dig("metadata", "volumeId").presence || resource[:name]
          points = Array(container["data"]).filter_map do |point|
            at = Telemetry.parse_time(point["ts"])
            [ at, point["value"].to_f ] if at && !point["value"].nil?
          end
          Telemetry::Series.new(label: label, points: points)
        end
        Telemetry::Chart.new(title: "#{METRIC_TITLES.fetch(metric, metric)} of #{resource[:name]}", unit: unit, series: series,
                             from: started, to: ended, link: page_of(environment_row, resource))
      end
    end
  end
end
