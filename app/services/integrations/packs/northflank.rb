module Integrations
  module Packs
    # Northflank for one project per environment: what runs there, its logs, its metrics and its builds, read with the
    # API token the workspace creates in Northflank. Every tool reads, except api_request, which reaches all of Northflank's
    # API inside the project when the token's role allows it and an admin switched it on.
    class Northflank < NativePack
      # The environment row's credentials, which only this pack reads.
      API_TOKEN = "api_token".freeze
      PROJECT = "project".freeze

      PROVIDER = "Northflank".freeze
      PROVIDER_KEY = "northflank".freeze
      GITHUB = "github".freeze
      APP_ROOT = "https://app.northflank.com".freeze
      OBSERVE = "observe".freeze
      OBSERVE_LOGS = "logs".freeze
      OBSERVE_METRICS = "metrics".freeze
      KIND_SERVICES = "services".freeze
      KIND_ADDONS = "addons".freeze
      KIND_JOBS = "jobs".freeze

      LOG_TYPES = %w[runtime build ingress mesh cdn backup restore].freeze
      DEFAULT_LOG_TYPE = LOG_TYPES.first
      METRICS = %w[cpu memory requests http4xxResponses http5xxResponses networkIngress networkEgress tcpConnectionsOpen diskUsage bandwidth].freeze
      DEFAULT_METRICS = %w[cpu memory requests http5xxResponses].freeze
      UNITS = { "pct" => "%", "vCPU" => "vCPU", "mb" => "MB", "kbps" => "kbps", "rps" => "requests/s", "count" => "count" }.freeze
      METRIC_TITLES = {
        "cpu" => "CPU", "memory" => "Memory", "requests" => "Requests", "http4xxResponses" => "4xx responses",
        "http5xxResponses" => "5xx responses", "networkIngress" => "Network in", "networkEgress" => "Network out",
        "tcpConnectionsOpen" => "Open TCP connections", "diskUsage" => "Disk usage", "bandwidth" => "Bandwidth"
      }.freeze
      # What a baseline reads for each kind on the map, and where Northflank keeps that kind.
      BASELINE_METRICS = {
        ResourceMap::KIND_SERVICE => [ KIND_SERVICES, %w[requests http4xxResponses http5xxResponses cpu memory] ],
        ResourceMap::KIND_DATABASE => [ KIND_ADDONS, %w[cpu memory diskUsage] ]
      }.freeze
      AVERAGED_UNIT = "pct".freeze
      COUNT_UNIT = "count".freeze
      PER_MINUTE = "per minute".freeze
      DISK_METRIC = "diskUsage".freeze
      API_METHODS = NorthflankApi::VERBS.keys.freeze
      # Where Northflank answers with values that are secrets, so only their names come back.
      SECRET_PATHS = /environment|argument|secret|credential|registr|key|token|password|connection/i
      API_RESULT_LIMIT = 6_000
      PROJECT_PATH = %r{\A[A-Za-z0-9_-]+(/[A-Za-z0-9_-]+)*\z}
      DEFAULT_MINUTES = 60
      MAX_MINUTES = 7 * 24 * 60
      LOG_LIMIT = 200
      BUILD_LIMIT = 10
      DEPLOYMENT_LIMIT = 20
      CONTAINER_LIMIT = 50
      RUN_LIMIT = 20
      BACKUPS_SHOWN = 3
      # Northflank's container states, as the model should read them.
      CONTAINER_STATES = {
        "TASK_RUNNING" => "running", "TASK_STARTING" => "starting", "TASK_STAGING" => "scheduled", "TASK_KILLING" => "stopping",
        "TASK_KILLED" => "stopped", "TASK_FAILED" => "failed", "TASK_FINISHED" => "finished"
      }.freeze

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

      tool :api_request,
           description: "Any call to Northflank's API inside the project: read or change services, databases, jobs, builds, " \
                        "deployments, volumes, domains, secrets and the rest, with the method and body Northflank's API docs give. " \
                        "The path is relative to the project, such as services/web/restart. Load the northflank_fixes skill first. " \
                        "It lists common fixes and their paths",
           params_schema: {
             "type" => "object",
             "properties" => {
               "method" => { "type" => "string", "enum" => API_METHODS },
               "path" => { "type" => "string", "description" => "Inside the project, such as services/web/scale" },
               "body" => { "type" => "object", "description" => "The JSON body Northflank's API takes for this call (optional)" }
             },
             "required" => %w[method path]
           },
           read_only: false

      tool :search_logs,
           description: "Log lines from one service or database, newest first, at most #{LOG_LIMIT}. Filter by text or a regular " \
                        "expression, and by log type: runtime for what the app prints, build, ingress for HTTP requests reaching it " \
                        "where Northflank has ingress logs switched on for the account. The app's runtime logs usually carry each " \
                        "request's path too",
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

      tool :describe_resource,
           description: "How one service or database is set up and how it stands now. A service: its rollout status, " \
                        "instances, plan, the repository, branch and commit it runs or the image, ephemeral storage, health " \
                        "checks and ports. A database: its type and version, status, replicas, storage, plan, network access, " \
                        "secret rotation, pending actions and latest backups",
           params_schema: { "type" => "object", "properties" => { "resource" => RESOURCE }, "required" => [ "resource" ] },
           read_only: true

      tool :list_deployments,
           description: "A service's deployments, newest first: when each went out, the commit or image, how many instances, " \
                        "and why (such as a build, a template or release run, or a change to its settings) and by whom. " \
                        "Use it to see what changed before something broke",
           params_schema: {
             "type" => "object",
             "properties" => {
               "resource" => RESOURCE,
               "limit" => { "type" => "integer", "description" => "At most this many deployments (optional, #{DEPLOYMENT_LIMIT})" }
             },
             "required" => [ "resource" ]
           },
           read_only: true

      tool :list_containers,
           description: "The containers of a service or database, newest first, running and past, with each one's state " \
                        "(running, starting, stopped, failed, finished) and when it started and last changed. Many short lived " \
                        "containers mean restarts",
           params_schema: {
             "type" => "object",
             "properties" => {
               "resource" => RESOURCE,
               "limit" => { "type" => "integer", "description" => "At most this many containers (optional, #{CONTAINER_LIMIT})" }
             },
             "required" => [ "resource" ]
           },
           read_only: true

      tool :list_jobs,
           description: "The jobs in the project, cron and manual, with whether each is suspended. Use job_runs for how a job's runs went",
           params_schema: { "type" => "object", "properties" => {} },
           read_only: true

      tool :job_runs,
           description: "A job's runs, newest first, with each one's outcome (succeeded, running, failed), when it started and " \
                        "finished, and how many attempts failed",
           params_schema: {
             "type" => "object",
             "properties" => {
               "job" => { "type" => "string", "description" => "The job, by name or id, as list_jobs shows it" },
               "limit" => { "type" => "integer", "description" => "At most this many runs (optional, #{RUN_LIMIT})" }
             },
             "required" => [ "job" ]
           },
           read_only: true

      tool :build_logs,
           description: "Log lines from a service's builds, newest first, at most #{LOG_LIMIT}. Name a build from recent_builds " \
                        "to read one build, such as the one that failed",
           params_schema: {
             "type" => "object",
             "properties" => {
               "resource" => RESOURCE,
               "build" => { "type" => "string", "description" => "A build's id, as recent_builds shows it (optional, every build in the range)" },
               "text" => { "type" => "string", "description" => "Only lines containing this text (optional)" },
               "regex" => { "type" => "string", "description" => "Only lines matching this regular expression (optional)" },
               "limit" => { "type" => "integer", "description" => "At most this many lines (optional, #{LOG_LIMIT})" },
               **RANGE
             },
             "required" => [ "resource" ]
           },
           read_only: true

      # The project is not a secret, so it is a connect field in the registry, shown on the connection's card, and read
      # with ConnectionSettings#field.
      def self.credential_fields
        [
          CredentialField.new(key: API_TOKEN, label: "API token", secret: true, placeholder: "nf-...",
                              hint: "A Northflank API token whose role can read the project, its services, databases and jobs, and view observability. For Halon to apply fixes, its role can also update services.")
        ]
      end

      # Reads the project with the token, so a wrong token or project is said on the form before anything is saved.
      def self.credential_refusal(values, region: nil, fields: {})
        token = values[API_TOKEN].to_s.strip
        project = fields.to_h.stringify_keys[PROJECT].to_s.strip
        return "Paste an API token." if token.empty?
        return "Enter the project id." if project.empty?

        NorthflankApi.new(token).project(project)
        nil
      rescue NorthflankApi::Error => error
        "Northflank refused this token or project. #{error.message}"
      end

      def self.store_credentials!(environment_row, values)
        environment_row.store_credential!(API_TOKEN, values[API_TOKEN].to_s.strip)
      end

      def list_resources(environment_row:, arguments:)
        project = project_of(environment_row)
        rows = resources(environment_row).map do |resource|
          "#{resource[:name]} (#{resource[:id]}), #{resource[:type]}, #{resource[:status]}"
        end
        link = project_link(environment_row)
        return Telemetry.result("Project #{project} has no services or databases.", link: link) if rows.empty?

        Telemetry.result("Project #{project}, #{rows.size} services and databases.\n#{rows.join("\n")}", link: link)
      end

      def search_logs(environment_row:, arguments:)
        resource = find_resource(environment_row, arguments["resource"])
        started, ended = Telemetry.range(arguments, default_minutes: DEFAULT_MINUTES, max_minutes: MAX_MINUTES)
        limit = arguments["limit"].to_i.positive? ? [ arguments["limit"].to_i, LOG_LIMIT ].min : LOG_LIMIT
        query = {
          "startTime" => started.utc.iso8601, "endTime" => ended.utc.iso8601, "lineLimit" => limit, "direction" => "backward",
          "type" => arguments["type"].presence_in(LOG_TYPES) || DEFAULT_LOG_TYPE, "textIncludes" => arguments["text"].presence,
          "regexIncludes" => arguments["regex"].presence, "textNotIncludes" => arguments["exclude"].presence
        }
        begin
          found = api(environment_row).logs(project_of(environment_row), resource[:kind], resource[:id], query)
        rescue NorthflankApi::NotEnabled
          return Telemetry.result(not_enabled(query["type"]), link: observe_link(environment_row, resource, OBSERVE_LOGS, range_query(started, ended)))
        end
        lines = found.map do |line|
          Telemetry::LogLine.new(at: Telemetry.parse_time(line["ts"]) || ended, source: line["containerId"].to_s, text: line["log"])
        end
        link = observe_link(environment_row, resource, OBSERVE_LOGS, log_search(arguments).merge(range_query(started, ended)))
        Telemetry.result(Telemetry.logs_text(lines, asked: "#{resource[:name]} from #{started.utc.iso8601} to #{ended.utc.iso8601}", limit: limit), link: link)
      end

      # Only inside the connected project, so a change can never reach another project or the team.
      def api_request(environment_row:, arguments:)
        verb = arguments["method"].to_s.upcase
        fail!("method must be one of #{API_METHODS.join(', ')}.") unless API_METHODS.include?(verb)
        path = arguments["path"].to_s.strip.delete_prefix("/")
        fail!("path must be inside the project, such as services/web/restart.") unless path.match?(PROJECT_PATH)
        body = arguments["body"]
        fail!("body must be an object.") unless body.nil? || body.is_a?(Hash)
        fail!("body holds what looks like a secret. Never send a credential through Northflank's API.") if secret?(body)

        # Worked out first, so a change that went through is never reported as failed for want of its link.
        link = change_link(environment_row, path)
        answer = begin
          api(environment_row).request(verb, project_of(environment_row), path, body)
        rescue NorthflankApi::NotEnabled
          raise
        rescue NorthflankApi::Error => error
          raise unless error.message.start_with?("Northflank answered 403")

          fail!("#{error.message}. The API token's role cannot make this change. In Northflank, give the role permission " \
                "to update services (Project, Services, General, Update), then run it again.")
        end
        Telemetry.result("Northflank answered #{verb} #{path}.#{"\n#{answer_text(path, answer)}" if answer.present?}", link: link)
      end

      # Northflank's answer, with anything that looks like a credential redacted, and only the names where the path is one
      # that holds secrets, so no secret reaches the model, the chat or the ledger.
      def answer_text(path, answer)
        shown = path.match?(SECRET_PATHS) ? names_only(answer) : hide_secret_fields(answer)
        Chat::SecretFree::SECRET_PATTERNS.reduce(shown.to_json) { |text, (name, pattern)| text.gsub(pattern, "[REDACTED:#{name}]") }
                                         .truncate(API_RESULT_LIMIT)
      end

      # What describes a secret rather than holding it stays readable.
      DESCRIBING = %w[id name description type secretType priority tags createdAt updatedAt].freeze

      # A field anywhere in an answer whose name says it holds secrets, such as a service's runtimeEnvironment, keeps only
      # its names.
      def hide_secret_fields(value)
        case value
        when Hash then value.to_h { |key, inner| [ key, key.to_s.match?(SECRET_PATHS) ? names_only(inner) : hide_secret_fields(inner) ] }
        when Array then value.map { |inner| hide_secret_fields(inner) }
        else value
        end
      end

      def names_only(value)
        case value
        when Hash
          value.to_h do |key, inner|
            kept = DESCRIBING.include?(key) && !inner.is_a?(Hash) && !inner.is_a?(Array)
            [ key, kept ? inner : (inner.is_a?(Hash) || inner.is_a?(Array) ? names_only(inner) : "[hidden]") ]
          end
        when Array then value.map { |inner| names_only(inner) }
        else "[hidden]"
        end
      end

      def query_metrics(environment_row:, arguments:)
        resource = find_resource(environment_row, arguments["resource"])
        started, ended = Telemetry.range(arguments, default_minutes: DEFAULT_MINUTES, max_minutes: MAX_MINUTES)
        asked = Array(arguments["metrics"]) & METRICS
        asked = DEFAULT_METRICS if asked.empty?
        query = { "startTime" => started.utc.iso8601, "endTime" => ended.utc.iso8601, "metricTypes" => asked }
        data = api(environment_row).metrics(project_of(environment_row), resource[:kind], resource[:id], query)
        link = observe_link(environment_row, resource, OBSERVE_METRICS, range_query(started, ended))
        charts = asked.filter_map { |metric| chart(resource, metric, data[metric], started, ended, link) if data[metric] }
        Telemetry.result("#{resource[:name]}\n#{Telemetry.charts_text(charts)}", charts: charts, link: link)
      end

      def recent_builds(environment_row:, arguments:)
        resource = find_resource(environment_row, arguments["resource"])
        fail! "#{resource[:name]} is a database, and only services have builds." unless resource[:kind] == KIND_SERVICES

        limit = arguments["limit"].to_i.positive? ? [ arguments["limit"].to_i, BUILD_LIMIT ].min : BUILD_LIMIT
        builds = api(environment_row).builds(project_of(environment_row), resource[:id], limit: limit)
        link = resource_link(environment_row, resource, "builds")
        return Telemetry.result("#{resource[:name]} has no builds.", link: link) if builds.empty?

        rows = builds.map do |build|
          outcome = build["concluded"] ? (build["success"] ? "succeeded" : "failed") : build["status"].to_s.downcase
          [ build["createdAt"], outcome, build["branch"], build["sha"].to_s.first(12), ("build #{build['id']}" if build["id"].present?),
            build["message"].presence ].compact.join(", ")
        end
        Telemetry.result("Latest #{rows.size} builds of #{resource[:name]}, newest first.\n#{rows.join("\n")}", link: link)
      end

      def describe_resource(environment_row:, arguments:)
        resource = find_resource(environment_row, arguments["resource"])
        lines = resource[:kind] == KIND_SERVICES ? service_lines(environment_row, resource) : database_lines(environment_row, resource)
        Telemetry.result(lines.compact.join("\n"), link: resource_link(environment_row, resource))
      end

      def list_deployments(environment_row:, arguments:)
        resource = find_resource(environment_row, arguments["resource"])
        fail! "#{resource[:name]} is a database, and only services have deployments." unless resource[:kind] == KIND_SERVICES

        deployments = api(environment_row).deployments(project_of(environment_row), resource[:id], limit: limit(arguments, DEPLOYMENT_LIMIT))
        link = resource_link(environment_row, resource, "deployments")
        return Telemetry.result("#{resource[:name]} has no deployments.", link: link) if deployments.empty?

        rows = deployments.map { |deployment| deployment_line(deployment) }
        Telemetry.result("Latest #{rows.size} deployments of #{resource[:name]}, newest first.\n#{rows.join("\n")}", link: link)
      end

      def list_containers(environment_row:, arguments:)
        resource = find_resource(environment_row, arguments["resource"])
        containers = api(environment_row).containers(project_of(environment_row), resource[:kind], resource[:id], limit: limit(arguments, CONTAINER_LIMIT))
        link = observe_link(environment_row, resource)
        return Telemetry.result("#{resource[:name]} has no containers.", link: link) if containers.empty?

        rows = containers.sort_by { |container| -container["createdAt"].to_i }.map do |container|
          state = CONTAINER_STATES.fetch(container["status"].to_s, container["status"].to_s.downcase)
          "#{container['name']}, #{state}, started #{epoch(container['createdAt'])}, last changed #{epoch(container['updatedAt'])}"
        end
        running = containers.count { |container| container["status"] == "TASK_RUNNING" }
        failed = containers.count { |container| container["status"] == "TASK_FAILED" }
        Telemetry.result("#{resource[:name]}: #{running} running, #{failed} failed, #{rows.size} listed, newest first.\n#{rows.join("\n")}", link: link)
      end

      def list_jobs(environment_row:, arguments:)
        project = project_of(environment_row)
        rows = api(environment_row).jobs(project).map do |job|
          [ "#{job['name']} (#{job['id']})", "#{job['jobType']} job", ("suspended" if job["suspended"]) ].compact.join(", ")
        end
        link = project_link(environment_row, KIND_JOBS)
        return Telemetry.result("Project #{project} has no jobs.", link: link) if rows.empty?

        Telemetry.result("Project #{project}, #{rows.size} jobs.\n#{rows.join("\n")}", link: link)
      end

      def job_runs(environment_row:, arguments:)
        project = project_of(environment_row)
        wanted = arguments["job"].to_s.strip.downcase
        fail! "Say which job, by name or id. list_jobs shows them." if wanted.empty?

        job = api(environment_row).jobs(project).find { |each| [ each["id"], each["name"] ].compact.map(&:downcase).include?(wanted) }
        fail! "No job called #{arguments['job']} in this project. list_jobs shows what there is." unless job

        runs = api(environment_row).job_runs(project, job["id"], limit: limit(arguments, RUN_LIMIT))
        link = project_link(environment_row, KIND_JOBS, job["id"], "runs")
        return Telemetry.result("#{job['name']} has no runs.", link: link) if runs.empty?

        rows = runs.map do |run|
          [ run["startedAt"], run["status"].to_s.downcase, ("finished #{run['concludedAt']}" if run["concludedAt"]),
            ("#{run['failed']} failed attempts" if run["failed"].to_i.positive?) ].compact.join(", ")
        end
        Telemetry.result("Latest #{rows.size} runs of #{job['name']}, newest first.\n#{rows.join("\n")}", link: link)
      end

      def build_logs(environment_row:, arguments:)
        resource = find_resource(environment_row, arguments["resource"])
        fail! "#{resource[:name]} is a database, and only services have builds." unless resource[:kind] == KIND_SERVICES

        started, ended = Telemetry.range(arguments, default_minutes: DEFAULT_MINUTES, max_minutes: MAX_MINUTES)
        line_limit = limit(arguments, LOG_LIMIT)
        query = {
          "startTime" => started.utc.iso8601, "endTime" => ended.utc.iso8601, "lineLimit" => line_limit, "direction" => "backward",
          "buildId" => arguments["build"].presence, "textIncludes" => arguments["text"].presence, "regexIncludes" => arguments["regex"].presence
        }
        lines = api(environment_row).build_logs(project_of(environment_row), resource[:id], query).map do |line|
          Telemetry::LogLine.new(at: Telemetry.parse_time(line["ts"]) || ended, source: arguments["build"].to_s, text: line["log"])
        end
        asked = "the builds of #{resource[:name]} from #{started.utc.iso8601} to #{ended.utc.iso8601}"
        link = resource_link(environment_row, resource, "builds", arguments["build"].presence)
        Telemetry.result(Telemetry.logs_text(lines, asked: asked, limit: line_limit), link: link)
      end

      # The project on the resource map: its services, build services, databases and jobs, the repositories they build
      # from and the domains they serve, with the links Northflank declares between them. A list the token may not read
      # is a gap in the map, not a failed sweep.
      def map_of(environment_row)
        project = project_of(environment_row)
        api = api(environment_row)
        details = api.services(project).map { |listed| api.service(project, listed["id"]).presence || listed }
        team = details.filter_map { |service| team_of(service["appId"]) }.first
        account = [ team, project ].compact.join("/")
        mapping = MapReading.new(account) { |kind, id| app_link(environment_row, team, kind, id)&.url }

        details.each { |service| mapping.service(service) }
        api.addons(project).each { |addon| mapping.database(addon) }
        gaps = []
        begin
          api.jobs(project).each { |job| mapping.job(job) }
        rescue NorthflankApi::Error => error
          gaps << "Jobs could not be read: #{error.message}"
        end
        ResourceMap::Snapshot.new(resources: mapping.resources, links: mapping.links, gaps: gaps)
      end

      # What normal looks like for its services and databases, one metrics read each. A week comes back in coarse steps,
      # so readings are grouped to the step before containers are added up (a percentage is averaged, a disk is its
      # fullest volume), and a count per step becomes a count per minute, which a live reading can be compared with. A
      # resource Northflank cannot read keeps yesterday's baselines, and being asked to slow down stops the whole read.
      def baselines_of(environment_row, resources, window)
        project = project_of(environment_row)
        api = api(environment_row)
        resources.flat_map do |resource|
          kind, metrics = BASELINE_METRICS[resource.kind]
          next [] unless kind

          query = { "startTime" => window.begin.utc.iso8601, "endTime" => window.end.utc.iso8601, "metricTypes" => metrics }
          data = api.metrics(project, kind, resource.external_id, query)
          metrics.filter_map { |metric| baseline(resource, metric, data[metric]) if data[metric] }
        rescue NorthflankApi::RateLimited
          raise
        rescue NorthflankApi::Error => error
          Rails.logger.warn("baseline_sweep.resource_failed resource=#{resource.id} error=#{error.message}")
          []
        end
      end

      # Builds the snapshot for map_of, one resource at a time.
      class MapReading
        SERVICE_KINDS = { "build" => ResourceMap::KIND_BUILD_SERVICE }.freeze

        attr_reader :resources, :links

        # page_of answers a resource's page in Northflank's app, given the path segment its kind uses and its id.
        def initialize(account, &page_of)
          @account = account
          @page_of = page_of
          @resources = []
          @links = []
        end

        def service(service)
          kind = SERVICE_KINDS.fetch(service["serviceType"].to_s, ResourceMap::KIND_SERVICE)
          internal = service.dig("deployment", "internal") || {}
          status = service.dig("status", "deployment", "status") || service.dig("status", "build", "status")
          found = add(kind, service["id"], service["name"], status: status&.downcase, page: [ KIND_SERVICES, service["id"] ],
                      details: {
                        "type" => service["serviceType"], "instances" => service.dig("deployment", "instances"),
                        "plan" => service.dig("billing", "deploymentPlan"), ResourceMap::DEPLOYED_COMMIT => internal["deployedSHA"],
                        "branch" => internal["branch"]
                      }.compact)

          built = internal["nfObjectId"]
          link(found, key(ResourceMap::KIND_BUILD_SERVICE, built), ResourceMap::RELATION_RUNS_BUILDS_OF) if built.present? && built != service["id"]
          repository(found, service["vcsData"])
          Array(service["ports"]).select { |port| port["public"] }.flat_map { |port| Array(port["domains"]) }.uniq.each { |host| domain(found, host) }
        end

        def database(addon)
          add(ResourceMap::KIND_DATABASE, addon["id"], addon["name"], status: addon["status"].to_s.downcase.presence,
              page: [ KIND_ADDONS, addon["id"] ], details: { "type" => addon.dig("spec", "type") }.compact)
        end

        def job(job)
          add(ResourceMap::KIND_JOB, job["id"], job["name"], page: [ KIND_JOBS, job["id"] ],
              details: { "type" => job["jobType"], "suspended" => job["suspended"] }.compact)
        end

        private

        def add(kind, id, name, page:, status: nil, details: {})
          url = @page_of.call(*page)
          found = ResourceMap::Found.new(provider: PROVIDER_KEY, account: @account, kind: kind, external_id: id.to_s,
                                         name: name.presence || id.to_s, status: status, url: url, details: details)
          @resources << found
          found.key
        end

        def key(kind, id) = [ PROVIDER_KEY, @account, kind, id.to_s ]

        def link(from, to, relation)
          @links << ResourceMap::FoundLink.new(from: from, to: to, relation: relation)
        end

        # The repository a service builds from, read off its vcsData. Only GitHub's addresses are read.
        def repository(from, source)
          url = source.to_h["projectUrl"].to_s
          path = URI.parse(url).path.to_s.delete_prefix("/").delete_suffix(".git") if url.start_with?("https://github.com/")
          return if path.blank?

          owner = path.split("/").first
          found = ResourceMap::Found.new(provider: GITHUB, account: owner, kind: ResourceMap::KIND_REPOSITORY, external_id: path,
                                         name: path, url: "https://github.com/#{path}")
          @resources << found
          link(from, found.key, ResourceMap::RELATION_BUILT_FROM)
        end

        def domain(service, host)
          found = ResourceMap.domain(host)
          @resources << found
          link(found.key, service, ResourceMap::RELATION_SERVED_BY)
        end
      end

      def check_health!(environment_row)
        api(environment_row).project(project_of(environment_row))
      rescue NorthflankApi::Error => error
        fail! error.message
      end

      private

      def api(environment_row)
        token = ConnectionSettings.of(environment_row).credential(API_TOKEN)
        fail! "This environment has no Northflank token. Reconnect it on the Integrations page." if token.blank?

        NorthflankApi.new(token)
      end

      def project_of(environment_row) = ConnectionSettings.of(environment_row).field(PROJECT) || fail!("This environment has no Northflank project. Reconnect it.")

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

      def limit(arguments, most) = arguments["limit"].to_i.positive? ? [ arguments["limit"].to_i, most ].min : most

      def epoch(seconds) = seconds ? Time.zone.at(seconds.to_i).utc.iso8601 : "unknown"

      def service_lines(environment_row, resource)
        service = api(environment_row).service(project_of(environment_row), resource[:id])
        rollout = service.dig("status", "deployment") || {}
        deployment = service["deployment"] || {}
        source = deployment["internal"] || {}
        [
          "#{resource[:name]}, #{service['serviceType']} service",
          ("Rollout: #{rollout['status']}, #{rollout['reason']}, since #{rollout['lastTransitionTime']}. COMPLETED means the latest deployment rolled out and is serving, not that the process ended." if rollout.any?),
          "Instances: #{deployment['instances'] || 'none'}#{", plan #{service.dig('billing', 'deploymentPlan')}" if service.dig('billing', 'deploymentPlan')}",
          running_from(source, deployment),
          ("Ephemeral storage: #{deployment.dig('storage', 'ephemeralStorage', 'storageSize')} MB, a container writing past it is evicted" if deployment.dig("storage", "ephemeralStorage", "storageSize")),
          health_lines(service["healthChecks"]),
          port_lines(service["ports"])
        ]
      end

      def running_from(source, deployment)
        return "Runs #{source['repository']}, branch #{source['branch']}, deployed commit #{source['deployedSHA']}" if source["repository"]
        return "Runs builds of #{source['nfObjectId']}, deployed commit #{source['deployedSHA']}" if source["nfObjectId"]

        image = deployment.dig("external", "imagePath") || deployment["imageUrl"]
        "Runs the image #{image}" if image
      end

      def health_lines(checks)
        return "Health checks: none, so Northflank cannot tell a hung process from a healthy one." if checks.blank?

        rows = checks.map do |check|
          target = [ check["protocol"], check["port"] && "port #{check['port']}", check["path"], check["cmd"] ].compact.join(" ")
          "#{check['type']}: #{target}, every #{check['periodSeconds']}s, timeout #{check['timeoutSeconds']}s, fails after #{check['failureThreshold']} misses"
        end
        "Health checks:\n#{rows.join("\n")}"
      end

      def port_lines(ports)
        return nil if ports.blank?

        rows = ports.map { |port| "#{port['name']} #{port['internalPort']} #{port['protocol']}, #{port['public'] ? 'public' : 'private'}" }
        "Ports: #{rows.join('; ')}"
      end

      def database_lines(environment_row, resource)
        project = project_of(environment_row)
        addon = api(environment_row).addon(project, resource[:id])
        config = addon.dig("spec", "config") || {}
        deployment = config["deployment"] || {}
        networking = config["networking"] || {}
        rotation = config["secretRotation"]
        pending = Array(addon.dig("spec", "pendingActions")).map { |action| "#{action['type']} since #{action['createdAt']}" }
        [
          "#{resource[:name]}, #{addon.dig('spec', 'type')} #{config['versionTag']} database, version #{config['lifecycleStatus'] || 'support unknown'}",
          "Status: #{addon['status']}",
          "Replicas: #{deployment['replicas']}, storage #{deployment['storageSize']} MB #{deployment['storageClass']}, plan #{deployment['planId']}. Storage and replicas can only grow.",
          "TLS #{networking['tlsEnabled'] ? 'on' : 'off'}, access from outside the project #{networking['externalAccessEnabled'] ? 'on' : 'off'}",
          ("Secret rotation: #{rotation['status']}, started #{rotation['startedAt']}#{", finished #{rotation['completedAt']}" if rotation['completedAt']}" if rotation),
          ("Pending: #{pending.join('; ')}" if pending.any?),
          backup_lines(environment_row, project, resource)
        ]
      end

      def backup_lines(environment_row, project, resource)
        backups = api(environment_row).backups(project, resource[:id], limit: BACKUPS_SHOWN)
        return "Backups: none" if backups.empty?

        "Latest backups: #{backups.map { |backup| "#{backup['createdAt']} #{backup['status']}" }.join('; ')}"
      rescue NorthflankApi::Error => error
        "Backups could not be read: #{error.message}"
      end

      def deployment_line(deployment)
        commit = deployment["commit"]
        what = commit ? "#{commit['sha'].to_s.first(12)} \"#{commit['message'].to_s.lines.first.to_s.strip}\" by #{commit['author']}" : "image #{deployment.dig('image', 'imagePath') || deployment.dig('image', 'image')}:#{deployment.dig('image', 'tag')}"
        who = deployment.dig("reason", "user", "name")
        [ deployment["createdAt"], ("active" if deployment["active"]), "#{deployment['instances']} instances", what,
          "reason #{deployment.dig('reason', 'id') || 'unknown'}#{" by #{who}" if who}" ].compact.join(", ")
      end

      # Addresses in Northflank's app, as its pages write them. appId starts with the team, as in /team/project/service.
      # A service's logs and metrics are under its Observe page, and their address carries the search and time range.
      # A database keeps its main page, since its Observe address has not been checked.
      def resource_link(environment_row, resource, *rest, query: {})
        app_link(environment_row, team_of(resource[:app_id]), resource[:kind], resource[:id], *rest, query: query)
      end

      def secret?(body) = body && Chat::SecretFree::SECRET_PATTERNS.values.any? { |pattern| body.to_json.match?(pattern) }

      # The page of what was changed, when the path names a service, database or job, and the project's otherwise.
      def change_link(environment_row, path)
        kind, id = path.split("/").first(2)
        resource = resources(environment_row).find { |each| each[:kind] == kind && each[:id] == id } if [ KIND_SERVICES, KIND_ADDONS ].include?(kind)
        resource ? resource_link(environment_row, resource) : project_link(environment_row, *([ kind, id ] if kind == KIND_JOBS))
      end

      def observe_link(environment_row, resource, tab = nil, query = {})
        return resource_link(environment_row, resource) unless resource[:kind] == KIND_SERVICES

        resource_link(environment_row, resource, OBSERVE, tab, query: query)
      end

      # A job or the project has no appId of its own here, so the team is read off any service or database in it.
      def project_link(environment_row, *rest)
        team = resources(environment_row).filter_map { |resource| team_of(resource[:app_id]) }.first
        app_link(environment_row, team, *rest)
      end

      def app_link(environment_row, team, *rest, query: {})
        return nil if team.blank?

        segments = [ "t", team, "project", project_of(environment_row), *rest.compact ].map { |part| ERB::Util.url_encode(part) }
        url = "#{APP_ROOT}/#{segments.join('/')}"
        url = "#{url}?#{query.compact.to_query}" if query.compact.any?
        Telemetry::Link.new(provider: PROVIDER, url: url)
      end

      def team_of(app_id) = app_id.to_s.split("/").reject(&:empty?).first

      def range_query(started, ended) = { "range" => "custom", "startDate" => started.utc.iso8601(3), "endDate" => ended.utc.iso8601(3) }

      # The page searches one way at a time, so the link carries the first filter the search used, in the order text,
      # regex, exclude.
      def log_search(arguments)
        text, regex, exclude = arguments.values_at("text", "regex", "exclude").map(&:presence)
        return { "searchQuery" => text, "matchType" => "match", "queryType" => "text" } if text
        return { "searchQuery" => regex, "matchType" => "match", "queryType" => "regex" } if regex
        return { "searchQuery" => exclude, "matchType" => "noMatch", "queryType" => "text" } if exclude

        {}
      end

      def baseline(resource, metric, data)
        raw_unit = data.dig("metricInfo", "metricUnit").to_s
        series = Array(data["values"]).map do |container|
          Array(container["data"]).filter_map do |point|
            at = Telemetry.parse_time(point["ts"])
            [ at.to_i, point["value"].to_f ] if at && !point["value"].nil?
          end
        end
        step = step_of(series)
        return nil unless step

        by_step = series.flatten(1).group_by { |at, _| at - (at % step) }.transform_values { |points| points.map(&:last) }
        per_minute = raw_unit == COUNT_UNIT ? 60.0 / step : 1
        points = by_step.sort.map { |at, values| [ Time.zone.at(at), combine(metric, raw_unit, values) * per_minute ] }
        unit = raw_unit == COUNT_UNIT ? PER_MINUTE : UNITS.fetch(raw_unit, raw_unit.presence)
        ResourceMap::Baseline::Found.new(key: resource.key, metric: metric, label: METRIC_TITLES.fetch(metric, metric), unit: unit, points: points)
      end

      # The spacing Northflank chose for the range, as the most common gap between one container's readings.
      def step_of(series)
        gaps = series.flat_map { |points| points.map(&:first).sort.each_cons(2).map { |first, second| second - first } }.select(&:positive?)
        gaps.tally.max_by(&:last)&.first
      end

      def combine(metric, raw_unit, values)
        return values.max if metric == DISK_METRIC
        return values.sum / values.size if raw_unit == AVERAGED_UNIT

        values.sum
      end

      # Not a broken connection, only a kind of log this account does not have, so the agent is pointed at one it does.
      def not_enabled(type)
        "Northflank has not switched on #{type} logs for this account, so there are none to read. The connection works. " \
          "Ask for type #{DEFAULT_LOG_TYPE} instead, the service's own lines, which usually log each request's path and status."
      end

      def chart(resource, metric, data, started, ended, link)
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
                             from: started, to: ended, link: link&.url)
      end
    end
  end
end
