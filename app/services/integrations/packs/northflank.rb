module Integrations
  module Packs
    # Northflank for the projects an environment reads, one, several or every one its token can read (the project
    # connect field, a scope). It reads what runs there, its logs, its metrics and its builds, with the API token the
    # workspace creates in Northflank. Every tool reads, except api_request, which reaches all of Northflank's API inside
    # one project when the token's role allows it and it is switched on, and add_workflow_webhook (WorkflowWebhooks). A call reaches one project, the one it
    # names or the one its resource lives in (Integrations::Scopes), and a listing named none lists every project.
    class Northflank < NativePack
      # The environment row's credentials, which only this pack reads.
      API_TOKEN = "api_token".freeze
      PROJECT = "project".freeze

      PROVIDER = "Northflank".freeze
      PROVIDER_KEY = "northflank".freeze
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
      # What a service list puts on the map: the services, the domains they serve and the repositories they build from.
      MAP_SERVICE_KINDS = [ ResourceMap::KIND_SERVICE, ResourceMap::KIND_BUILD_SERVICE, ResourceMap::KIND_DOMAIN, ResourceMap::KIND_REPOSITORY ].freeze
      AVERAGED_UNIT = "pct".freeze
      COUNT_UNIT = "count".freeze
      PER_MINUTE = "per minute".freeze
      DISK_METRIC = "diskUsage".freeze
      API_METHODS = NorthflankApi::VERBS.keys.freeze
      # Where Northflank answers with values that are secrets, so only their names come back.
      SECRET_PATHS = /environment|argument|secret|credential|registr|key|token|password|connection/i
      API_RESULT_LIMIT = 6_000
      PROJECT_PATH = %r{\A[A-Za-z0-9_-]+(/[A-Za-z0-9_-]+)*\z}
      QUERY_NAME = /\A[A-Za-z0-9_.]{1,64}\z/
      QUERY_VALUE_LIMIT = 500
      # Seen in a real chat, Halon guessed a path to create a pipeline, which Northflank's API has no call for, three
      # times over. A path Northflank does not know, or a method it does not take there, sends it to the reference.
      MISSING_CALL = [ "Northflank answered 404", "Northflank answered 405" ].freeze
      NO_SUCH_CALL = "Northflank's API may not offer this call, or what the path names does not exist. Check the call in " \
                     "the northflank_fixes skill's API reference before trying again, and never send the same call again. " \
                     "When the reference does not list it, say Northflank's API does not offer it and give the steps in " \
                     "Northflank's dashboard instead.".freeze
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
                        "whether each is running, deploying or failed, every project's when the connection reaches several and " \
                        "none is named. Use it first to find the name to pass to the other tools",
           params_schema: { "type" => "object", "properties" => {} },
           read_only: true

      tool :api_request,
           description: "Any call to Northflank's API inside the project: read or change services, databases, jobs, builds, " \
                        "deployments, volumes, secrets, release flows and the rest. The path is relative to the project, such as " \
                        "services/web/restart, and query options go in query, never in the path. A list answers one page. " \
                        "Pass per_page, at most 100, and while the answer's pagination says hasNextPage, pass its cursor " \
                        "for the next page. Load the northflank_fixes skill first. It lists common fixes, " \
                        "and its API reference lists every call Northflank's API offers with the body and query options each " \
                        "takes, so a call it does not list does not exist",
           params_schema: {
             "type" => "object",
             "properties" => {
               "method" => { "type" => "string", "enum" => API_METHODS },
               "path" => { "type" => "string", "description" => "Inside the project, such as services/web/scale" },
               "query" => { "type" => "object",
                            "description" => "Query options by name, each text, a number, true or false, such as {\"per_page\": 100, " \
                                             "\"cursor\": \"<the cursor the last page gave>\"}. Only the names the API reference " \
                                             "lists for this call (optional)" },
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

      tool :build_history,
           description: "A service's recent builds, with each one's status, when it started and finished and how long it took, " \
                        "and how long finished ones usually take. Northflank keeps no end time for a deployment, so this reads builds",
           params_schema: {
             "type" => "object",
             "properties" => {
               "resource" => RESOURCE,
               "name" => { "type" => "string", "description" => "Only runs of this kind, build (optional)" },
               "limit" => { "type" => "integer", "description" => "At most this many builds (optional, #{BUILD_LIMIT * 2})" }
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
           description: "The jobs in the project, cron and manual, with whether each is suspended, every project's when the " \
                        "connection reaches several and none is named. Use job_runs for how a job's runs went",
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

      include WorkflowWebhooks

      # The project is not a secret, so it is a connect field in the registry, shown on the connection's card, and read
      # with ConnectionSettings#field.
      def self.credential_fields
        [
          CredentialField.new(key: API_TOKEN, label: "API token", secret: true, placeholder: "nf-...",
                              hint: "A Northflank API token whose role can list and read the projects, their services, databases and jobs, and view observability. To link services to the databases their secret groups hold, its role can also read secret groups. For Halon to apply fixes, its role can also update services. To follow changes live, its role can also read, create and delete notification integrations.")
        ]
      end

      # Reads each project chosen with the token, or lists them for every one it can read, so a wrong token or project
      # is said on the form before anything is saved.
      def self.credential_refusal(values, region: nil, fields: {})
        token = values[API_TOKEN].to_s.strip
        projects = Array(fields.to_h.stringify_keys[PROJECT]).map { |each| each.to_s.strip }.compact_blank
        return "Paste an API token." if token.empty?
        return "Choose at least one project, or all the token can read." if projects.empty?

        api = NorthflankApi.new(token)
        if projects == [ IntegrationProvider::ConnectField::ALL ]
          return "This token can read no Northflank projects. Give its role Project, Projects, Read." if api.projects.items.empty?
        else
          projects.each do |project|
            api.project(project)
          rescue NorthflankApi::Error => error
            return Sentence.all("Northflank refused this token or project #{project}.", error)
          end
        end
        nil
      rescue NorthflankApi::Error => error
        Sentence.all("Northflank refused this token or project.", error)
      end

      # The projects the token can read (GET /v1/projects, @northflank/js-client ListProjectsResult, each with its id and
      # name), which needs the token's role to read projects.
      def self.scope_options(values, region: nil, fields: {})
        token = values.to_h.stringify_keys[API_TOKEN].to_s.strip
        raise NativePack::Error, "Paste an API token first." if token.empty?

        NorthflankApi.new(token).projects.items.map do |project|
          IntegrationProvider::ConnectOption.new(value: project["id"].to_s, label: project["name"].presence || project["id"].to_s)
        end
      rescue NorthflankApi::Error => error
        raise NativePack::Error, Sentence.all("Northflank did not list this token's projects.", error)
      end

      # A tool names what it acts on by resource or job, and api_request by the service, addon or job its path starts with.
      def self.scope_references(arguments)
        kind, id = arguments["path"].to_s.delete_prefix("/").split("/").first(2)
        [ arguments["resource"], arguments["job"], (id if [ KIND_SERVICES, KIND_ADDONS, KIND_JOBS ].include?(kind)) ]
      end

      def self.store_credentials!(environment_row, values)
        environment_row.store_credential!(API_TOKEN, values[API_TOKEN].to_s.strip)
      end

      def list_resources(environment_row:, arguments:)
        return every_project(environment_row) { |pack| pack.list_resources(environment_row: environment_row, arguments: arguments) } if every_scope?(environment_row)

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
        query = query_of(verb, path, arguments["query"])
        body = arguments["body"]
        fail!("body must be an object.") unless body.nil? || body.is_a?(Hash)
        fail_policy!("body holds what looks like a secret, and Firefight never sends a credential through Northflank's API.") if secret?(body)
        body = webhook_tokens_restored(environment_row, path, body) unless verb == "GET"

        # Worked out first, so a change that went through is never reported as failed for want of its link.
        link = change_link(environment_row, path)
        answer = begin
          api(environment_row).request(verb, project_of(environment_row), path, body, query)
        rescue NorthflankApi::NotEnabled
          raise
        rescue NorthflankApi::Error => error
          fail!(Sentence.all(error, NO_SUCH_CALL)) if error.message.start_with?(*MISSING_CALL)
          raise unless error.message.start_with?("Northflank answered 403")

          fail!(Sentence.all(error, "The API token's role cannot make this change. In Northflank, give the role permission " \
                                   "to update services (Project, Services, General, Update), then run it again."))
        end
        asked = query.any? ? "#{path}?#{URI.encode_www_form(query)}" : path
        Telemetry.result("Northflank answered #{verb} #{asked}.#{"\n#{answer_text(path, answer)}" if answer.present?}", link: link)
      end

      # A call the API reference lists takes only the names it gives, and any other call takes plain names. A value is
      # text, a number, true or false, and the client encodes it, so nothing in it can reach the path.
      def query_of(verb, path, query)
        return {} if query.nil?
        fail!("query must be an object of option names to values, such as {\"per_page\": 100}.") unless query.is_a?(Hash)

        listed = ApiReference.query_names(verb, path)
        query.to_h do |name, value|
          name = name.to_s
          fail!("#{name.inspect} is not a query option name.") unless name.match?(QUERY_NAME)
          if listed && !listed.include?(name)
            fail!("#{verb} #{path} takes no query option #{name}. #{listed.any? ? "The API reference lists #{listed.join(', ')} for it." : 'The API reference lists none for it.'}")
          end
          [ name, query_value(name, value) ]
        end.tap do |checked|
          fail_policy!("query holds what looks like a secret, and Firefight never sends a credential through Northflank's API.") if secret?(checked)
        end
      end

      def query_value(name, value)
        fail!("The query option #{name} must be text, a number, true or false.") unless value.is_a?(String) || value.is_a?(Numeric) || value == true || value == false

        text = value.to_s
        fail!("The query option #{name} is too long or holds a control character.") if text.length > QUERY_VALUE_LIMIT || text.match?(/[[:cntrl:]]/)
        text
      end

      # Northflank's answer, with anything that looks like a credential redacted, and only the names where the path is one
      # that holds secrets, so no secret reaches the model, the chat or the ledger. Whether a list has another page comes
      # first, since a long answer is cut short at its end.
      def answer_text(path, answer)
        answer = answer.slice("pagination").merge(answer.except("pagination")) if answer.is_a?(Hash)
        shown = path.match?(SECRET_PATHS) ? names_only(answer) : hide_secret_fields(answer)
        Chat::SecretFree.redacted(shown.to_json)
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

      # A build's status (@northflank/js-client, GetServiceBuildsResult) in Firefight's words.
      BUILD_STATUSES = {
        "queued" => Capabilities::History::QUEUED, "pending" => Capabilities::History::QUEUED, "unschedulable" => Capabilities::History::QUEUED,
        "success" => Capabilities::History::SUCCEEDED, "failure" => Capabilities::History::FAILED,
        "submission_failure" => Capabilities::History::FAILED, "crashed" => Capabilities::History::FAILED,
        "aborted" => Capabilities::History::CANCELLED
      }.freeze

      # A build from createdAt, an ISO 8601 time, to buildConcludedAt, in Unix seconds (GetServiceBuildsResult).
      def build_history(environment_row:, arguments:)
        resource = find_resource(environment_row, arguments["resource"])
        fail! "#{resource[:name]} is a database, and only services have builds." unless resource[:kind] == KIND_SERVICES

        builds = api(environment_row).builds(project_of(environment_row), resource[:id], limit: limit(arguments, BUILD_LIMIT * 2))
        runs = builds.map do |build|
          Capabilities::History::Run.new(
            id: build["id"], name: "build", status: Capabilities::History.status(build["status"], BUILD_STATUSES),
            started_at: Telemetry.parse_time(build["createdAt"]),
            finished_at: (Time.zone.at(build["buildConcludedAt"].to_i).utc if build["buildConcludedAt"].to_i.positive?),
            detail: [ build["branch"], build["sha"].to_s.first(12).presence, build["message"].presence ].compact.join(", ").presence
          )
        end
        Capabilities::History.result(runs, what: resource[:name], link: resource_link(environment_row, resource, "builds"), name: arguments["name"])
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
        return every_project(environment_row) { |pack| pack.list_jobs(environment_row: environment_row, arguments: arguments) } if every_scope?(environment_row)

        project = project_of(environment_row)
        rows = api(environment_row).jobs(project).items.map do |job|
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

        job = api(environment_row).jobs(project).items.find { |each| [ each["id"], each["name"] ].compact.map(&:downcase).include?(wanted) }
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
      # from and the domains they serve, with the links Northflank declares between them. A list the token may not read,
      # or one cut short at NorthflankApi::MAX_PAGES, is a gap in the map, not a failed sweep.
      def map_of(environment_row)
        map_of_scopes(environment_row, kinds: MAP_KINDS) { |pack| pack.map_of_project(environment_row) }
      end

      # What a sweep puts on the map for one project.
      MAP_KINDS = [ *MAP_SERVICE_KINDS, ResourceMap::KIND_DATABASE, ResourceMap::KIND_JOB ].freeze

      def map_of_project(environment_row)
        project = project_of(environment_row)
        api = api(environment_row)
        services = api.services(project)
        details = services.items.map { |listed| api.service(project, listed["id"]).presence || listed }
        team = details.filter_map { |service| team_of(service["appId"]) }.first
        account = [ team, project ].compact.join("/")
        mapping = MapReading.new(account) { |kind, id| app_link(environment_row, team, kind, id)&.url }

        details.each { |service| mapping.service(service) }
        addons = api.addons(project)
        addons.items.each { |addon| mapping.database(addon) }
        gaps = []
        gaps << cut_short("services", MAP_SERVICE_KINDS) if services.incomplete?
        gaps << cut_short("databases", [ ResourceMap::KIND_DATABASE ]) if addons.incomplete?
        begin
          jobs = api.jobs(project)
          jobs.items.each { |job| mapping.job(job) }
          gaps << cut_short("jobs", [ ResourceMap::KIND_JOB ]) if jobs.incomplete?
        rescue NorthflankApi::Error => error
          gaps << ResourceMap::Gap.new(text: Sentence.join("Jobs could not be read", error), kinds: [ ResourceMap::KIND_JOB ])
        end
        groups = secret_groups(api, project, gaps)
        uses = details.flat_map { |service| service_uses(environment_row, mapping, service, groups) }
        ResourceMap::Snapshot.new(resources: mapping.resources, links: mapping.links, gaps: gaps, uses: uses)
      end

      # Only the service, addon or job a notification named, read again as the sweep reads it, a service with the settings
      # its secret groups give it. Gone only when Northflank answers not found for it, under the account the map already
      # has the project in, and otherwise nil, for a sweep to say. A service's id may be a build service's, so both are
      # gone. nil for a scope Northflank cannot narrow to.
      def map_refresh(environment_row, scope)
        reader = REFRESHERS[scope.kind]
        return unless scope.external_id && reader
        return project_holding(environment_row, scope)&.map_refresh(environment_row, scope) if every_scope?(environment_row)

        project = project_of(environment_row)
        api = api(environment_row)
        found = begin
          api.public_send(reader, project, scope.external_id)
        rescue NorthflankApi::NotFound
          {}
        end
        return gone(environment_row, scope) if found.blank?

        mapping = MapReading.new([ team_of(found["appId"]), project ].compact.join("/")) { |kind, id| app_link(environment_row, team_of(found["appId"]), kind, id)&.url }
        gaps = []
        uses = []
        case scope.kind
        when ResourceMap::KIND_DATABASE then mapping.database(found)
        when ResourceMap::KIND_JOB then mapping.job(found)
        else
          mapping.service(found)
          uses = service_uses(environment_row, mapping, found, secret_groups(api, project, gaps))
        end
        ResourceMap::Snapshot.new(resources: mapping.resources, links: mapping.links, gaps: gaps, uses: uses)
      end

      # The read for each kind a notification names. A service's kind is not known until it is read.
      REFRESHERS = { nil => :service, ResourceMap::KIND_DATABASE => :addon, ResourceMap::KIND_JOB => :job }.freeze
      private_constant :REFRESHERS

      # The settings a service runs with, from the secret groups that apply to it and its own runtime variables, and the
      # databases those groups link it to. A build service runs nothing.
      def service_uses(environment_row, mapping, service, groups)
        return [] if service["serviceType"] == "build"

        key = mapping.key_of(ResourceMap::KIND_SERVICE, service["id"])
        inherited = groups.select { |group| group.applies_to?(service["id"], service["tags"]) }.sort_by(&:priority)
        inherited.each { |group| group.addons.each { |addon, variables| mapping.uses(key, addon, variables) } }
        values = inherited.map(&:variables).reduce({}, :merge).merge(service["runtimeEnvironment"].to_h)
        ResourceMap::Use.read(from: key, workspace: environment_row.integration.workspace, values: values)
      end
      private :service_uses

      def gone(environment_row, scope)
        project = project_of(environment_row)
        account = ResourceMap::Resource.present.where(integration_environment: environment_row, provider: PROVIDER_KEY)
                                       .where("account = :project OR account LIKE :within", project: project, within: "%/#{ResourceMap::Resource.sanitize_sql_like(project)}")
                                       .pick(:account)
        return unless account

        kinds = scope.kind ? [ scope.kind ] : [ ResourceMap::KIND_SERVICE, ResourceMap::KIND_BUILD_SERVICE ]
        ResourceMap::Snapshot.new(resources: [], gone: kinds.map { |kind| [ PROVIDER_KEY, account, kind, scope.external_id ] })
      end
      private :gone

      # A secret group as it applies to services, with the variables it gives them, the addons linked to it with the names
      # each linked key reaches a service under, and its restrictions (@northflank/js-client, ListSecretsResult). An
      # unrestricted group reaches every service in the project, and a restricted one the services it names or whose
      # tags match.
      SecretGroup = Data.define(:priority, :restrictions, :variables, :addons) do
        def applies_to?(service_id, tags)
          return true unless restrictions["restricted"]
          return true if Array(restrictions["nfObjects"]).any? { |object| object["id"] == service_id }

          wanted = Array(restrictions["tags"])
          return false if wanted.empty?

          restrictions["tagMatchCondition"] == "and" ? (wanted - Array(tags)).empty? : wanted.intersect?(Array(tags))
        end
      end
      # Being asked to slow down while reading secret groups stops reading them, and the map's own reads go on.
      SLOWED = "Northflank asked Firefight to slow down, so the rest of the secret groups were not read this time.".freeze
      SECRETS_PERMISSION = "Its role needs to read secret groups (Project, Secrets) for the settings services inherit and the " \
                           "databases linked to them.".freeze

      # The project's secret groups, one list and one read per group, within an hourly budget a sweep shares with the
      # rest of the account's calls. A list the token may not read is a settings gap that names the permission.
      def secret_groups(api, project, gaps)
        listed = api.secret_groups(project)
        gaps << ResourceMap::Gap.new(text: "Only the first #{listed.items.size} secret groups were read.", kinds: [], settings: true) if listed.incomplete?
        listed.items.filter_map do |group|
          details = api.secret_group(project, group["id"])
          SecretGroup.new(priority: group["priority"].to_i, restrictions: group["restrictions"].to_h,
                          variables: details.dig("secrets", "variables").to_h, addons: linked_addons(details))
        end
      rescue NorthflankApi::RateLimited
        gaps << ResourceMap::Gap.new(text: SLOWED, kinds: [], settings: true)
        []
      rescue NorthflankApi::Error => error
        gaps << ResourceMap::Gap.new(text: Sentence.all(Sentence.join("Secret groups could not be read", error), SECRETS_PERMISSION), kinds: [], settings: true)
        []
      end

      # Each addon a group links, with the variable names its keys reach services under, from the details' addonSecrets.
      # Their variables come as names, or keys with the aliases a link gives them, so each is read as a name.
      def linked_addons(details)
        Array(details["addonSecrets"]).to_h do |addon|
          variables = addon["variables"]
          names = case variables
          when Hash then variables.keys
          when Array then variables.flat_map { |each| each.is_a?(Hash) ? Array(each["aliases"]).presence || [ each["keyName"] || each["name"] ] : [ each ] }
          else []
          end
          [ addon["id"].to_s, names.compact.map(&:to_s) ]
        end
      end

      # What normal looks like for its services and databases, one metrics read each. A week comes back in coarse steps,
      # so readings are grouped to the step before containers are added up (a percentage is averaged, a disk is its
      # fullest volume), and a count per step becomes a count per minute, which a live reading can be compared with. A
      # resource Northflank cannot read keeps yesterday's baselines, and being asked to slow down stops the whole read.
      def baselines_of(environment_row, resources, window)
        return by_scope(environment_row, resources) { |pack, group| pack.baselines_of(environment_row, group, window) } unless scope

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

        # A service uses a database a secret group links, through the variables it names, one link however many groups
        # link it.
        def uses(from, addon_id, variables)
          to = key(ResourceMap::KIND_DATABASE, addon_id)
          index = @links.index { |link| link.from == from && link.to == to && link.relation == ResourceMap::RELATION_USES }
          found = ResourceMap::FoundLink.new(from: from, to: to, relation: ResourceMap::RELATION_USES,
                                             variables: ((index ? @links[index].variables : []) + variables).uniq.sort)
          index ? @links[index] = found : @links << found
        end

        def key_of(kind, id) = key(kind, id)

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

        # The repository a service builds from, read off its vcsData, on whichever code host it is.
        def repository(from, source)
          found = ResourceMap.repository_of(source.to_h["projectUrl"])
          return unless found

          @resources << found
          link(from, found.key, ResourceMap::RELATION_BUILT_FROM)
        end

        def domain(service, host)
          found = ResourceMap.domain(host)
          @resources << found
          link(found.key, service, ResourceMap::RELATION_SERVED_BY)
        end
      end

      # Reads each project the connection reaches, so one the token can no longer read is said on the connection.
      def check_health!(environment_row)
        ConnectionSettings.of(environment_row).scopes.each { |project| api(environment_row).project(project) }
      rescue NorthflankApi::Error => error
        fail! error.message
      end

      private

      # A list past NorthflankApi::MAX_PAGES, said in the map's gaps.
      def cut_short(what, kinds)
        most = NorthflankApi::MAX_PAGES * NorthflankApi::PAGE_SIZE
        ResourceMap::Gap.new(text: "The project has more than #{most} #{what}, so only the first #{most} are on the map.", kinds: kinds)
      end

      def api(environment_row)
        token = ConnectionSettings.of(environment_row).credential(API_TOKEN)
        fail! "This environment has no Northflank token. Reconnect it on the Integrations page." if token.blank?

        NorthflankApi.new(token)
      end

      def project_of(environment_row) = scope!(environment_row)

      # A listing of every project the connection reaches, each read by a pack of its own and headed with its project.
      def every_project(environment_row)
        settings = ConnectionSettings.of(environment_row)
        texts = settings.scopes.map do |project|
          Array(yield(scoped(project))["content"]).filter_map { |part| part["text"] }.join("\n")
        end
        Telemetry.result(texts.join("\n\n"), link: nil)
      end

      # The pack of the project a notification's service, addon or job is in, the one the map has it in, or else the first
      # project that has it, for one added since the last sweep. nil when none does.
      def project_holding(environment_row, scope)
        on_map = ResourceMap::Resource.present.where(workspace_id: environment_row.integration.workspace_id, provider: PROVIDER_KEY, external_id: scope.external_id)
                                      .where("resource_map_resources.integration_environment_id = :row OR resource_map_resources.sightings ? :row", row: environment_row.id.to_s)
                                      .pick(Arel.sql("details ->> '#{ResourceMap::SCOPE}'"))
        return scoped(on_map) if on_map.present?

        reader = REFRESHERS[scope.kind]
        ConnectionSettings.of(environment_row).scopes.lazy.map { |project| scoped(project) }.find do |pack|
          api(environment_row).public_send(reader, pack.scope, scope.external_id).present?
        rescue NorthflankApi::NotFound
          false
        end
      end

      def resources(environment_row)
        @resources ||= begin
          project = project_of(environment_row)
          services = api(environment_row).services(project).items.map do |service|
            status = service.dig("status", "deployment", "status") || service.dig("status", "build", "status") || "unknown"
            { kind: KIND_SERVICES, id: service["id"], name: service["name"], type: "#{service['serviceType']} service",
              status: status.to_s.downcase, app_id: service["appId"] }
          end
          addons = api(environment_row).addons(project).items.map do |addon|
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
        "Ports:\n#{rows.map { |row| "  #{row}" }.join("\n")}"
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
          ("Pending: #{pending.to_sentence}" if pending.any?),
          backup_lines(environment_row, project, resource)
        ]
      end

      def backup_lines(environment_row, project, resource)
        backups = api(environment_row).backups(project, resource[:id], limit: BACKUPS_SHOWN)
        return "Backups: none" if backups.empty?

        "Latest backups: #{backups.map { |backup| "#{backup['createdAt']} #{backup['status']}" }.to_sentence}"
      rescue NorthflankApi::Error => error
        Sentence.join("Backups could not be read", error)
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

        site = ConnectionSettings.of(environment_row).site
        return nil if site.blank?

        segments = [ "t", team, "project", project_of(environment_row), *rest.compact ].map { |part| ERB::Util.url_encode(part) }
        url = "#{site.chomp('/')}/#{segments.join('/')}"
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
