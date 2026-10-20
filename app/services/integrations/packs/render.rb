module Integrations
  module Packs
    # Render for the workspaces an environment reads, one, several or every one its API key can read (the workspace
    # connect field, a scope). It reads their services, Postgres databases, Key Value instances and workflows, and their
    # logs, metrics, deploys, events and runs (Runs), with the API key a person creates in Render. A call reaches one
    # workspace, the one it names or the one its resource lives in (Integrations::Scopes), and a listing named none lists
    # every workspace. Every tool reads, except the restart, rollback and scale Halon uses to apply fixes and the deploy
    # and suspend changes (Controls). Paths, parameters and answers are the ones in Render's OpenAPI spec
    # (api-docs.render.com/openapi/render-public-api-1.json).
    class Render < NativePack
      # The environment row's credentials, which only this pack reads.
      API_KEY = "api_key".freeze
      WORKSPACE = "workspace".freeze

      PROVIDER = "Render".freeze
      PROVIDER_KEY = "render".freeze

      # Render's service types (spec, schema serviceType), and how each sits on the map.
      WEB_SERVICE = "web_service".freeze
      PRIVATE_SERVICE = "private_service".freeze
      BACKGROUND_WORKER = "background_worker".freeze
      CRON_JOB = "cron_job".freeze
      STATIC_SITE = "static_site".freeze
      POSTGRES = "postgres".freeze
      KEY_VALUE = "key_value".freeze
      # A workflow runs tasks on demand (render.com/docs/workflows), read from /workflows rather than /services.
      WORKFLOW = "workflow".freeze
      KINDS = {
        WEB_SERVICE => ResourceMap::KIND_SERVICE, PRIVATE_SERVICE => ResourceMap::KIND_SERVICE, BACKGROUND_WORKER => ResourceMap::KIND_SERVICE,
        CRON_JOB => ResourceMap::KIND_JOB, STATIC_SITE => ResourceMap::KIND_SITE, POSTGRES => ResourceMap::KIND_DATABASE,
        KEY_VALUE => ResourceMap::KIND_DATABASE, WORKFLOW => ResourceMap::KIND_WORKFLOW
      }.freeze
      TYPE_WORDS = {
        WEB_SERVICE => "web service", PRIVATE_SERVICE => "private service", BACKGROUND_WORKER => "background worker",
        CRON_JOB => "cron job", STATIC_SITE => "static site", POSTGRES => "Postgres database", KEY_VALUE => "Key Value instance",
        WORKFLOW => "workflow"
      }.freeze
      DATASTORES = [ POSTGRES, KEY_VALUE ].freeze
      # What has no deploys or service events of its own.
      NOT_SERVICES = [ *DATASTORES, WORKFLOW ].freeze
      # The kinds a Render service is on the map as, by its type.
      SERVICE_KINDS = KINDS.except(*NOT_SERVICES).values.uniq.freeze
      # A workflow's page, as Render's CLI opens it (render-oss/cli, pkg/dashboard/dashboard.go, wf on the default
      # dashboard address in pkg/config/config.go). Render's API gives a workflow no dashboardUrl.
      WORKFLOW_PAGE = "https://dashboard.render.com/wf/%<id>s".freeze
      # Render scales web services, private services and background workers (render.com/docs/scaling).
      SCALABLE = [ WEB_SERVICE, PRIVATE_SERVICE, BACKGROUND_WORKER ].freeze
      # The restart endpoint is not supported for cron jobs (spec, POST /services/{serviceId}/restart), and a static
      # site runs no instance to restart.
      RESTARTABLE = [ WEB_SERVICE, PRIVATE_SERVICE, BACKGROUND_WORKER, POSTGRES ].freeze
      SUSPENDED = "suspended".freeze

      # The log types Render names (spec, GET /logs type): app for what the code prints, request for HTTP requests
      # reaching a web service on a Pro workspace or higher, build for builds.
      LOG_TYPES = %w[app request build].freeze
      # Render answers at most 100 lines a call (spec, GET /logs limit).
      LOG_LIMIT = 100
      DEPLOY_LIMIT = 20
      EVENT_LIMIT = 50
      EVENT_MINUTES = 24 * 60
      RECENT_EVENTS = 10

      # Each metric a tool takes, the endpoint that answers it and what it applies to. HTTP metrics are kept for web
      # services only and active connections for datastores only (spec, paths /metrics/*). Latency is a quantile of a web
      # service's requests (/metrics/http-latency, quantile) and disk usage its persistent disk's (/metrics/disk-usage).
      # The CPU and memory limits are what the plan allows, instances how many a service ran, replication lag how many
      # seconds a Postgres replica is behind, and bandwidth what a web service or static site sent, read without a
      # resolution, which its endpoint does not take (spec, GET /metrics/bandwidth).
      Metric = Data.define(:path, :title, :applies, :query, :resolution) do
        def initialize(query: {}, resolution: true, **) = super
      end
      COMPUTE = [ WEB_SERVICE, PRIVATE_SERVICE, BACKGROUND_WORKER, CRON_JOB, *DATASTORES ].freeze
      METRICS = {
        "cpu" => Metric.new(path: "cpu", title: "CPU", applies: COMPUTE),
        "memory" => Metric.new(path: "memory", title: "Memory", applies: COMPUTE),
        "requests" => Metric.new(path: "http-requests", title: "Requests", applies: [ WEB_SERVICE ]),
        "http_4xx" => Metric.new(path: "http-requests", title: "4xx responses", applies: [ WEB_SERVICE ], query: { "aggregateBy" => "statusCode" }),
        "http_5xx" => Metric.new(path: "http-requests", title: "5xx responses", applies: [ WEB_SERVICE ], query: { "aggregateBy" => "statusCode" }),
        "active_connections" => Metric.new(path: "active-connections", title: "Active connections", applies: DATASTORES),
        "latency_p95" => Metric.new(path: "http-latency", title: "Latency, 95th percentile", applies: [ WEB_SERVICE ], query: { "quantile" => 0.95 }),
        "disk" => Metric.new(path: "disk-usage", title: "Disk usage", applies: COMPUTE),
        "cpu_limit" => Metric.new(path: "cpu-limit", title: "CPU limit", applies: COMPUTE),
        "memory_limit" => Metric.new(path: "memory-limit", title: "Memory limit", applies: COMPUTE),
        "instance_count" => Metric.new(path: "instance-count", title: "Instances", applies: SCALABLE),
        "replication_lag" => Metric.new(path: "replication-lag", title: "Replication lag", applies: [ POSTGRES ]),
        "bandwidth" => Metric.new(path: "bandwidth", title: "Bandwidth", applies: [ WEB_SERVICE, STATIC_SITE ], resolution: false)
      }.freeze
      STATUS_CLASSES = { "http_4xx" => "4", "http_5xx" => "5" }.freeze
      DEFAULT_METRICS = { WEB_SERVICE => %w[cpu memory requests http_5xx], POSTGRES => %w[cpu memory active_connections],
                          KEY_VALUE => %w[cpu memory active_connections], STATIC_SITE => %w[bandwidth] }.freeze
      FALLBACK_METRICS = %w[cpu memory].freeze
      # What a baseline reads. Request counts are left out, since the spec does not say what span each reading counts.
      BASELINE_METRICS = %w[cpu memory active_connections].freeze
      # Render takes 30 seconds or more between readings (spec, resolutionSeconds), and about this many points reads well.
      MIN_RESOLUTION = 30
      POINTS = 60
      BASELINE_RESOLUTION = 3600
      STATUS_CODE = /\A[1-5]\d\d\z/

      RESOURCE = { "type" => "string", "description" => "A service, Postgres database or Key Value instance in the workspace, by name or id, as list_resources shows it" }.freeze

      tool :list_resources,
           summary: "Lists the services and datastores in the Render workspace and their state.",
           description: "The services, Postgres databases and Key Value instances in the Render workspace for this environment, " \
                        "with their type and whether each is running or suspended. Use it first to find the name to pass to the other tools",
           params_schema: { "type" => "object", "properties" => {} },
           read_only: true

      tool :describe_resource,
           summary: "Shows how one service, datastore or workflow is set up and how it stands now.",
           description: "How one service, datastore or workflow is set up and how it stands now. A service: whether it is suspended " \
                        "and why, its plan, region, instances or autoscaling, the instances running now, what it runs, its health " \
                        "check path, its latest deploy and its events of the last day. A datastore: its status, version, plan, disk, " \
                        "high availability and maintenance. A workflow: what it builds and runs, and its tasks",
           params_schema: { "type" => "object", "properties" => { "resource" => RESOURCE }, "required" => [ "resource" ] },
           read_only: true

      tool :search_logs,
           summary: "Searches app, request or build logs of one service or datastore.",
           description: "Log lines from one service or datastore, newest first, at most #{LOG_LIMIT}. Filter by text or a regular " \
                        "expression, and by type: app for what the code prints, request for HTTP requests reaching a web " \
                        "service (Pro workspaces and higher), build for its builds",
           params_schema: {
             "type" => "object",
             "properties" => {
               "resource" => RESOURCE,
               "text" => { "type" => "string", "description" => "Only lines containing this text (optional)" },
               "regex" => { "type" => "string", "description" => "Only lines matching this regular expression, in RE2 syntax (optional)" },
               "type" => { "type" => "string", "enum" => LOG_TYPES, "description" => "Which logs (optional, every type)" },
               "deploy" => { "type" => "string", "description" => "Only the time this deploy ran, by its id, when no start is given (optional)" },
               "job" => { "type" => "string", "description" => "Only this one-off job's lines, by its id as run_history with name job shows it (optional)" },
               "task_run" => { "type" => "string", "description" => "A workflow's lines of this task run only, by its id as run_history on the workflow shows it (optional)" },
               "limit" => { "type" => "integer", "description" => "At most this many lines (optional, #{LOG_LIMIT})" },
               **Capabilities::RANGE
             },
             "required" => [ "resource" ]
           },
           read_only: true

      tool :query_metrics,
           summary: "Shows CPU, memory, disk and request metrics of a service or datastore.",
           description: "Metrics of one service or datastore over time: CPU, memory and persistent disk usage and the CPU and memory " \
                        "its plan allows, for a service how many instances ran, for a web service requests, 4xx and 5xx responses, " \
                        "the latency 95% of its requests finished within and the bandwidth it sent, for a static site its bandwidth, " \
                        "for a datastore its active connections, and for a Postgres replica how far behind it is. " \
                        "Returns min, average, max and latest per instance, and the person sees each metric as a chart",
           params_schema: {
             "type" => "object",
             "properties" => {
               "resource" => RESOURCE,
               "metrics" => { "type" => "array", "items" => { "type" => "string", "enum" => METRICS.keys },
                              "description" => "Which metrics (optional, the usual ones for the resource)" },
               **Capabilities::RANGE
             },
             "required" => [ "resource" ]
           },
           read_only: true

      tool :deploy_history,
           summary: "Shows a service's recent deploys with how long each took against the usual.",
           description: "A service's recent deploys, each a build and its release, with its status, when it started and finished and " \
                        "how long it took, and how long finished ones usually take",
           params_schema: {
             "type" => "object",
             "properties" => {
               "resource" => RESOURCE,
               "name" => { "type" => "string", "description" => "Only runs of this kind, deploy (optional)" },
               "run" => { "type" => "string", "description" => "Only this deploy, by its id, with its build, pre-deploy and release and how each ended (optional)" },
               "limit" => { "type" => "integer", "description" => "At most this many deploys (optional, #{DEPLOY_LIMIT})" }
             },
             "required" => [ "resource" ]
           },
           read_only: true

      tool :list_deployments,
           summary: "Lists a service's deploys with status, commit and what triggered each.",
           description: "A service's deploys, newest first: when each started and finished, its status, the commit or image, and " \
                        "what triggered it (a new commit, a rollback, a manual deploy). The id of a live deploy is what " \
                        "rollback_deploy takes. Use it to see what changed before something broke",
           params_schema: {
             "type" => "object",
             "properties" => {
               "resource" => RESOURCE,
               "limit" => { "type" => "integer", "description" => "At most this many deploys (optional, #{DEPLOY_LIMIT})" }
             },
             "required" => [ "resource" ]
           },
           read_only: true

      tool :list_events,
           summary: "Lists a service's events such as failed instances, restarts and scaling.",
           description: "A service's events, newest first: instances that failed and why (ran out of memory, exited, failed health " \
                        "checks, timed out), restarts, deploys and builds that ended, scaling, disk usage warnings and suspensions. " \
                        "Use it when instances crash or restart",
           params_schema: {
             "type" => "object",
             "properties" => {
               "resource" => RESOURCE,
               "limit" => { "type" => "integer", "description" => "At most this many events (optional, #{EVENT_LIMIT})" },
               "minutes" => { "type" => "integer", "description" => "How far back from now, in minutes (optional, #{EVENT_MINUTES})" },
               "start" => Capabilities::RANGE["start"], "end" => Capabilities::RANGE["end"]
             },
             "required" => [ "resource" ]
           },
           read_only: true

      tool :restart_service,
           summary: "Restarts a service or Postgres database on the same code and settings.",
           description: "Restart a web service, private service, background worker or Postgres database. Render replaces every " \
                        "instance with the same code and settings, without downtime for a service, and does not pick up " \
                        "environment changes made since the last deploy",
           params_schema: { "type" => "object", "properties" => { "resource" => RESOURCE }, "required" => [ "resource" ] },
           read_only: false

      tool :rollback_deploy,
           summary: "Rolls a service back to an earlier deploy.",
           description: "Put a service back on an earlier deploy, by the deploy id list_deployments shows. Render puts that " \
                        "build back live without building again, while it still keeps the build. Autodeploy is left as it is, so " \
                        "while it is on the next commit deploys again. turn_off_autodeploy keeps the rollback",
           params_schema: {
             "type" => "object",
             "properties" => {
               "resource" => RESOURCE,
               "deploy" => { "type" => "string", "description" => "The deploy to go back to, by its id, such as dep-..." }
             },
             "required" => %w[resource deploy]
           },
           read_only: false

      tool :scale_service,
           summary: "Sets how many instances a service runs.",
           description: "Set how many instances a web service, private service or background worker runs. Render ignores it " \
                        "while autoscaling is on for the service",
           params_schema: {
             "type" => "object",
             "properties" => {
               "resource" => RESOURCE,
               "instances" => { "type" => "integer", "description" => "How many instances to run" }
             },
             "required" => %w[resource instances]
           },
           read_only: false

      tool :api_read,
           summary: "Reads other Render data such as disks, domains and blueprints.",
           description: "Anything else Render's API reads that the other tools do not cover, such as a service's disks, " \
                        "custom domains, environment groups, blueprints, projects or a deploy by its id. A GET to a path of " \
                        "Render's public API (#{RenderApi::API_ROOT}), as the API reference the render_api skill names writes " \
                        "it. A list answers one page: pass limit, at most 100, and the last item's cursor as cursor for the next, " \
                        "and pass ownerId to keep a list to this connection's workspace. Only reads, so it never changes anything. " \
                        "Environment variables and secret files come back as their names",
           params_schema: ApiReads.path_schema("/services/<service id>/custom-domains"),
           read_only: true

      include Runs
      include Controls

      def self.credential_fields
        [
          CredentialField.new(key: API_KEY, label: "API key", secret: true, placeholder: "rnd_...",
                              hint: "A Render API key, created under Account Settings, API Keys. It acts with the access of the person who created it. " \
                                    "Make it as a dedicated user, such as Firefight, so changes do not show as a teammate and the connection keeps working when someone leaves.")
        ]
      end

      # Reads each workspace chosen with the key, or lists them for every one it can read, so a wrong key or workspace is
      # said on the form before anything is saved.
      def self.credential_refusal(values, region: nil, fields: {})
        key = values[API_KEY].to_s.strip
        workspaces = Array(fields[WORKSPACE]).map { |each| each.to_s.strip }.compact_blank
        return "Paste an API key." if key.empty?
        return "Choose at least one workspace, or all the key can read." if workspaces.empty?

        api = RenderApi.new(key)
        return (scope_options(values).empty? ? "This API key can read no Render workspaces." : nil) if workspaces == [ IntegrationProvider::ConnectField::ALL ]

        workspaces.each do |workspace|
          api.owner(workspace)
        rescue RenderApi::Error => error
          return Sentence.join("Render refused this key or workspace#{" #{workspace}" if workspaces.many?}", error)
        end
        nil
      rescue NativePack::Error => error
        error.message
      rescue RenderApi::Error => error
        Sentence.join("Render refused this key or workspace", error)
      end

      # The workspaces the key can read (GET /v1/owners, "List workspaces", api-docs.render.com/reference/list-owners,
      # each an owner with its id, name and type). Only team workspaces, whose ids start tea-, as the connect field takes.
      TEAM_OWNER = "team".freeze

      def self.scope_options(values, region: nil, fields: {})
        key = values.to_h.stringify_keys[API_KEY].to_s.strip
        raise NativePack::Error, "Paste an API key first." if key.empty?

        RenderApi.new(key).owners.items.select { |owner| owner["type"] == TEAM_OWNER }.map { |owner| IntegrationProvider::ConnectOption.new(value: owner["id"].to_s, label: owner["name"].presence || owner["id"].to_s) }
      rescue RenderApi::Error => error
        raise NativePack::Error, Sentence.join("Render did not list this key's workspaces", error)
      end

      def self.store_credentials!(environment_row, values)
        environment_row.store_credential!(API_KEY, values[API_KEY].to_s.strip)
      end

      def list_resources(environment_row:, arguments:)
        return every_workspace(environment_row) { |pack| pack.list_resources(environment_row: environment_row, arguments: arguments) } if every_scope?(environment_row)

        rows = resources(environment_row).map { |resource| [ "#{resource[:name]} (#{resource[:id]})", TYPE_WORDS.fetch(resource[:type]), resource[:status] ].compact.join(", ") }
        workspace = ConnectionSettings.of(environment_row).scope_name(workspace_of(environment_row))
        cut = " Only the first #{rows.size} were read, so name a resource by its id to reach the rest." if resources_cut?(environment_row)
        text = rows.empty? ? "Workspace #{workspace} has no services, datastores or workflows." : "Workspace #{workspace}, #{rows.size} services, datastores and workflows.#{cut}\n#{rows.join("\n")}"
        text = "#{text}\n#{Sentence.join('Workflows could not be read', @workflows_unread)}" if @workflows_unread
        Telemetry.result(text, link: nil)
      end

      def describe_resource(environment_row:, arguments:)
        resource = find_resource(environment_row, arguments["resource"])
        lines = case resource[:type]
        when POSTGRES then postgres_lines(environment_row, resource)
        when KEY_VALUE then key_value_lines(environment_row, resource)
        when WORKFLOW then workflow_lines(environment_row, resource)
        else service_lines(environment_row, resource)
        end
        Telemetry.result(lines.compact.join("\n"), link: link(resource))
      end

      def search_logs(environment_row:, arguments:)
        resource = find_resource(environment_row, arguments["resource"])
        job = job_of(environment_row, resource, arguments["job"]) if arguments["job"].present?
        task_run = arguments["task_run"].to_s.strip.presence
        fail! "#{resource[:name]} is not a workflow, and only a workflow has task runs." if task_run && resource[:type] != WORKFLOW
        started, ended = Capabilities::Answers.range(job ? job_range(job, arguments) : deploy_range(environment_row, resource, arguments))
        limit = Capabilities::Answers.limit(arguments, LOG_LIMIT)
        # A regular expression goes in text between slashes, as Render's log search reads one.
        texts = [ arguments["text"].presence, (arguments["regex"].present? ? "/#{arguments['regex']}/" : nil) ].compact
        # A one-off job's lines are kept under the job's own id (spec, GET /logs, resource).
        query = {
          "ownerId" => workspace_of(environment_row), "resource" => job ? job["id"] : resource[:id], "startTime" => started.utc.iso8601,
          "endTime" => ended.utc.iso8601, "direction" => "backward", "limit" => limit, "text" => texts.presence,
          "type" => arguments["type"].presence_in(LOG_TYPES), "taskRun" => task_run
        }
        answer = api(environment_row).logs(query)
        lines = Array(answer["logs"]).map do |line|
          instance = Array(line["labels"]).find { |label| label["name"] == "instance" }&.dig("value")
          Telemetry::LogLine.new(at: Telemetry.parse_time(line["timestamp"]) || ended, source: instance.to_s, text: line["message"])
        end
        asked = "#{resource[:name]} from #{started.utc.iso8601} to #{ended.utc.iso8601}"
        # Render says when older lines in the range were left out, so the text says they were only then.
        shown_limit = answer["hasMore"] ? lines.size : lines.size + 1
        Telemetry.result(Telemetry.logs_text(lines, asked: asked, limit: shown_limit), link: link(resource))
      end

      # Render's logs carry no deploy id (spec, GET /logs), so one deploy's are the lines from when it was made to a little
      # after it finished.
      def deploy_range(environment_row, resource, arguments)
        return arguments if arguments["deploy"].blank? || arguments["start"].present?

        deploy = begin
          api(environment_row).deploy(resource[:id], arguments["deploy"].to_s.strip)
        rescue RenderApi::NotFound
          fail! "#{resource[:name]} has no deploy #{arguments['deploy']}. deploy_history lists its recent deploys."
        end
        from = Telemetry.parse_time(deploy["createdAt"] || deploy["startedAt"])
        return arguments unless from

        to = Telemetry.parse_time(deploy["finishedAt"])
        arguments.merge("start" => from.utc.iso8601, "end" => (to && (to + PHASE_MARGIN).utc.iso8601)).compact
      end
      private :deploy_range

      # The one-off job named, only one of this service.
      def job_of(environment_row, resource, asked)
        api(environment_row).job(resource[:id], asked.to_s.strip)
      rescue RenderApi::NotFound
        fail! "#{resource[:name]} has no one-off job #{asked}. run_history with name job lists its jobs."
      end
      private :job_of

      # A job's lines from when it was made to a little after it finished, when no start is given.
      def job_range(job, arguments)
        from = Telemetry.parse_time(job["createdAt"] || job["startedAt"])
        return arguments if arguments["start"].present? || from.nil?

        to = Telemetry.parse_time(job["finishedAt"])
        arguments.merge("start" => from.utc.iso8601, "end" => (to && (to + PHASE_MARGIN).utc.iso8601)).compact
      end
      private :job_range

      # What has no deploys or service events is refused in words, a datastore or a workflow.
      def services_only!(resource, why)
        return unless NOT_SERVICES.include?(resource[:type])

        fail! "#{resource[:name]} is a #{DATASTORES.include?(resource[:type]) ? 'datastore' : 'workflow'}, and #{why}"
      end
      private :services_only!

      def query_metrics(environment_row:, arguments:)
        resource = find_resource(environment_row, arguments["resource"])
        fail! "#{resource[:name]} is a workflow, and run_history reads how its runs went." if resource[:type] == WORKFLOW

        started, ended = Capabilities::Answers.range(arguments)
        asked = Array(arguments["metrics"]).map(&:to_s) & METRICS.keys
        asked = DEFAULT_METRICS.fetch(resource[:type], FALLBACK_METRICS) if asked.empty?
        kept, missing = asked.partition { |name| METRICS.fetch(name).applies.include?(resource[:type]) }
        resolution = [ ((ended - started) / POINTS).ceil, MIN_RESOLUTION ].max
        charts = kept.map { |name| chart(environment_row, resource, name, started, ended, resolution) }
        note = missing.any? ? "\nRender does not keep #{missing.join(', ')} for a #{TYPE_WORDS.fetch(resource[:type])}." : ""
        Telemetry.result("#{resource[:name]}\n#{Telemetry.charts_text(charts)}#{note}", charts: charts, link: link(resource))
      end

      def list_deployments(environment_row:, arguments:)
        resource = find_resource(environment_row, arguments["resource"])
        services_only!(resource, "only services have deploys.")

        deploys = api(environment_row).deploys(resource[:id], limit: Capabilities::Answers.limit(arguments, DEPLOY_LIMIT))
        return Telemetry.result("#{resource[:name]} has no deploys.", link: link(resource)) if deploys.empty?

        rows = deploys.map { |deploy| deploy_line(resource, deploy) }
        result = Telemetry.result("Latest #{rows.size} deploys of #{resource[:name]}, newest first. rollback_deploy takes a deploy id.\n#{rows.join("\n")}", link: link(resource))
        Capabilities::Deploys.with_deploys(result, deploys.map { |deploy| deploy_of(deploy) })
      end

      # The deploy serving now, and one that served and was replaced. Render says neither of a deploy in any other state.
      DEPLOY_LIVE = { "live" => true, "deactivated" => false }.freeze

      def deploy_of(deploy)
        Capabilities::Deploys::Deploy.new(
          id: deploy["id"], commit: deploy.dig("commit", "id"), version: deploy.dig("image", "ref"),
          status: Capabilities::Deploys.status(deploy["status"], DEPLOY_STATUSES),
          live: DEPLOY_LIVE[deploy["status"].to_s],
          started_at: deploy["startedAt"] || deploy["createdAt"], finished_at: deploy["finishedAt"]
        )
      end
      private :deploy_of

      # Render's deploy statuses (spec, schema deployStatus) in Firefight's words. A deploy that went live and was later
      # replaced finished well.
      DEPLOY_STATUSES = {
        "created" => Capabilities::History::QUEUED, "queued" => Capabilities::History::QUEUED,
        "build_in_progress" => Capabilities::History::RUNNING, "update_in_progress" => Capabilities::History::RUNNING,
        "pre_deploy_in_progress" => Capabilities::History::RUNNING, "live" => Capabilities::History::SUCCEEDED,
        "deactivated" => Capabilities::History::SUCCEEDED, "build_failed" => Capabilities::History::FAILED,
        "update_failed" => Capabilities::History::FAILED, "pre_deploy_failed" => Capabilities::History::FAILED,
        "canceled" => Capabilities::History::CANCELLED
      }.freeze

      # Each deploy from when it started (startedAt, or createdAt before Render began building it) to finishedAt.
      def deploy_history(environment_row:, arguments:)
        resource = find_resource(environment_row, arguments["resource"])
        services_only!(resource, "only services have deploys.")
        return one_deploy(environment_row, resource, arguments["run"]) if arguments["run"].present?

        deploys = api(environment_row).deploys(resource[:id], limit: Capabilities::Answers.limit(arguments, DEPLOY_LIMIT))
        runs = deploys.map { |deploy| deploy_run(resource, deploy) }
        Capabilities::History.result(runs, what: resource[:name], link: link(resource), name: arguments["name"])
      end

      # A deploy's phases as Render's service events name them (spec, serviceEvent and its details): the build by its
      # buildId, the pre-deploy command and the release by deployId. Each phase's log is read for the time it ran.
      PHASE_EVENTS = {
        "build" => %w[build_started build_ended], "pre-deploy" => %w[pre_deploy_started pre_deploy_ended],
        "deploy" => %w[deploy_started deploy_ended]
      }.freeze
      PHASE_STATUS_FIELDS = { "build" => "buildStatus", "pre-deploy" => "preDeployStatus", "deploy" => "deployStatus" }.freeze
      # Render's build, pre-deploy and deploy statuses (spec, enum succeeded, failed, canceled).
      PHASE_STATUSES = {
        "succeeded" => Capabilities::History::SUCCEEDED, "failed" => Capabilities::History::FAILED, "canceled" => Capabilities::History::CANCELLED
      }.freeze
      # A build prints to the build log and a release to the app log. A pre-deploy command's output is read from every type.
      PHASE_LOG_TYPES = { "build" => "build", "deploy" => "app" }.freeze
      # Events are read from a little before the deploy and past its end, since Render stamps them on its own clock.
      PHASE_MARGIN = 1.minute
      PHASE_EVENT_LIMIT = 100

      def deploy_run(resource, deploy)
        commit = deploy["commit"]
        Capabilities::History::Run.new(
          id: deploy["id"], name: "deploy", status: Capabilities::History.status(deploy["status"], DEPLOY_STATUSES),
          started_at: Telemetry.parse_time(deploy["startedAt"] || deploy["createdAt"]), finished_at: Telemetry.parse_time(deploy["finishedAt"]),
          url: deploy_url(resource, deploy["id"]),
          detail: commit ? "#{commit['id'].to_s.first(12)} #{commit['message'].to_s.lines.first.to_s.strip}".strip : deploy.dig("image", "ref")
        )
      end
      private :deploy_run

      def deploy_url(resource, id) = ("#{resource[:url]}/deploys/#{id}" if resource[:url].present? && id.present?)
      private :deploy_url

      def one_deploy(environment_row, resource, asked)
        id = asked.to_s.strip
        deploy = begin
          api(environment_row).deploy(resource[:id], id)
        rescue RenderApi::NotFound
          fail! "#{resource[:name]} has no deploy #{id}. deploy_history lists its recent deploys."
        end
        run = deploy_run(resource, deploy)
        run = run.with(parts: deploy_parts(environment_row, resource, deploy, run))
        page = run.url ? Telemetry::Link.new(provider: PROVIDER, url: run.url) : link(resource)
        Capabilities::History.result([ run ], what: resource[:name], link: page)
      end
      private :one_deploy

      def deploy_parts(environment_row, resource, deploy, run)
        from = Telemetry.parse_time(deploy["createdAt"]) || run.started_at || Time.current
        to = run.finished_at || Time.current
        events = api(environment_row).events(resource[:id], "startTime" => (from - PHASE_MARGIN).utc.iso8601, "endTime" => (to + PHASE_MARGIN).utc.iso8601,
                                                            "type" => PHASE_EVENTS.values.flatten, "limit" => PHASE_EVENT_LIMIT)
        events = events.sort_by { |event| event["timestamp"].to_s }
        ours = events.select { |event| event.dig("details", "deployId") == deploy["id"] }
        PHASE_EVENTS.filter_map do |phase, (started_type, ended_type)|
          phase_events = phase == "build" ? build_events(events, ours) : ours
          started = phase_events.find { |event| event["type"] == started_type }
          ended = phase_events.find { |event| event["type"] == ended_type }
          phase_part(resource, run, phase, started, ended) if started || ended
        end
      end
      private :deploy_parts

      # A deploy's build is the one its deploy_started names, or else the first build that started before it was
      # released, since a build's events carry the build's id and not the deploy's.
      def build_events(events, ours)
        released = ours.find { |event| event["type"] == "deploy_started" }
        build_id = released&.dig("details", "buildId") || events.find do |event|
          event["type"] == "build_started" && (released.nil? || event["timestamp"].to_s <= released["timestamp"].to_s)
        end&.dig("details", "buildId")
        build_id ? events.select { |event| event["type"].to_s.start_with?("build_") && event.dig("details", "buildId") == build_id } : []
      end
      private :build_events

      def phase_part(resource, run, phase, started, ended)
        started_at = Telemetry.parse_time(started&.dig("timestamp")) || run.started_at
        finished_at = Telemetry.parse_time(ended&.dig("timestamp"))
        status = if ended
          Capabilities::History.status(ended.dig("details", PHASE_STATUS_FIELDS.fetch(phase)), PHASE_STATUSES)
        else
          run.finished? ? run.status : Capabilities::History::RUNNING
        end
        reason = ended&.dig("details", "reason")
        reason = reason["failure"] if reason.is_a?(Hash) && reason.key?("failure")
        window = { "start" => started_at&.utc&.iso8601, "end" => (finished_at && (finished_at + PHASE_MARGIN).utc.iso8601) }
        Capabilities::History::Part.new(
          id: phase, name: phase, status: status, started_at: started_at, finished_at: finished_at, url: run.url, detail: failure_words(reason),
          log: { Capabilities::History::LOG_TOOL => "search_logs",
                 Capabilities::History::LOG_ARGUMENTS => { "resource" => resource[:id], "type" => PHASE_LOG_TYPES[phase], **window }.compact }
        )
      end
      private :phase_part

      def list_events(environment_row:, arguments:)
        resource = find_resource(environment_row, arguments["resource"])
        services_only!(resource, "Render lists events for services only.")

        started, ended = Telemetry.range(arguments, default_minutes: EVENT_MINUTES, max_minutes: Capabilities::MAX_MINUTES)
        events = api(environment_row).events(resource[:id], "startTime" => started.utc.iso8601, "endTime" => ended.utc.iso8601,
                                                            "limit" => Capabilities::Answers.limit(arguments, EVENT_LIMIT))
        return Telemetry.result("#{resource[:name]} had no events from #{started.utc.iso8601} to #{ended.utc.iso8601}.", link: link(resource)) if events.empty?

        rows = events.map { |event| event_line(event) }
        Telemetry.result("#{rows.size} events of #{resource[:name]}, newest first.\n#{rows.join("\n")}", link: link(resource))
      end

      def restart_service(environment_row:, arguments:)
        resource = find_resource(environment_row, arguments["resource"])
        unless RESTARTABLE.include?(resource[:type])
          fail! "Render cannot restart a #{TYPE_WORDS.fetch(resource[:type])} through its API. Redeploy it in Render instead."
        end

        resource[:type] == POSTGRES ? api(environment_row).restart_postgres(resource[:id]) : api(environment_row).restart_service(resource[:id])
        Telemetry.result("Render is restarting #{resource[:name]}. Its events show when the new instances are up.", link: link(resource))
      end

      def rollback_deploy(environment_row:, arguments:)
        resource = find_resource(environment_row, arguments["resource"])
        services_only!(resource, "only services have deploys to roll back to.")
        deploy = arguments["deploy"].to_s.strip
        fail! "Say which deploy to go back to, by the id list_deployments shows." if deploy.empty?

        started = api(environment_row).rollback(resource[:id], deploy)
        Telemetry.result("Render is rolling #{resource[:name]} back to deploy #{deploy}#{", as deploy #{started['id']}" if started['id']}. " \
                         "Autodeploy is left as it is, so while it is on the next commit to its branch deploys again. " \
                         "turn_off_autodeploy keeps the rollback.", link: link(resource))
      end

      def scale_service(environment_row:, arguments:)
        resource = find_resource(environment_row, arguments["resource"])
        unless SCALABLE.include?(resource[:type])
          fail! "Render scales web services, private services and background workers, and #{resource[:name]} is a #{TYPE_WORDS.fetch(resource[:type])}."
        end
        count = Integer(arguments["instances"], exception: false)
        fail! "instances must be a whole number, 0 or more." unless count && count >= 0

        service = api(environment_row).service(resource[:id])
        if service.dig("serviceDetails", "autoscaling", "enabled")
          fail! "Autoscaling is on for #{resource[:name]}, and Render ignores a set number of instances while it is. Change its " \
                "autoscaling minimum and maximum with set_autoscaling instead."
        end

        api(environment_row).scale(resource[:id], count)
        before = service.dig("serviceDetails", "numInstances")
        Telemetry.result("Render is scaling #{resource[:name]} to #{count} instances#{" from #{before}" if before}.", link: link(resource))
      end

      # Kept to the connection's workspaces, by the ownerId asked, the owner of what the path starts with and every owner
      # the answer names.
      def api_read(environment_row:, arguments:)
        call = begin
          ReadGuards::Render.reading(ApiReads::TOOL, arguments)
        rescue ReadGuards::Refused => error
          fail!(error.message)
        end
        path, query = call.values_at("path", "query")
        settings = ConnectionSettings.of(environment_row)
        api = api(environment_row)
        parent = parent_of(api, path)
        outside = ApiReads.outside_scopes(settings, [ query["ownerId"], *owners_in(parent), *path_owner(path) ], "workspaces")
        fail_policy!(outside) if outside

        answer = api.read(path, query)
        outside = ApiReads.outside_scopes(settings, owners_in(answer), "workspaces")
        fail_policy!("#{outside} Pass ownerId in query to keep a list to one workspace.") if outside

        text = ApiReads.answer(PROVIDER, ApiReads.asked(path, query), answer, secret: ReadGuards::Render.secret?(path))
        Telemetry.result(text, link: read_link(path, answer, parent))
      end

      # What Render names by an id of its own at the start of a path, whose answer says which workspace owns it.
      OWNED = %w[services postgres key-value redis env-groups projects blueprints disks].freeze
      OWNERS = "owners".freeze
      OWNER = "owner".freeze

      # The service, datastore or other owned thing a deeper path reads inside, such as the service of
      # /services/<id>/deploys, read first for its workspace and its page. nil for a path that is the thing itself or a
      # list, which the answer says the owner of.
      def parent_of(api, path)
        kind, id, deeper = path.delete_prefix("/").split("/", 3)
        return nil unless OWNED.include?(kind) && id.present? && deeper.present?

        api.read("/#{kind}/#{Http.segment(id)}", {})
      rescue RenderApi::NotFound
        nil
      end
      private :parent_of

      def path_owner(path)
        kind, id = path.delete_prefix("/").split("/", 3)
        kind == OWNERS && id.present? ? [ id ] : []
      end
      private :path_owner

      # Every workspace an answer names as an owner, a service's ownerId or a datastore's or project's owner.
      def owners_in(value)
        case value
        when Hash then [ value["ownerId"], (value[OWNER]["id"] if value[OWNER].is_a?(Hash)) ].compact + value.values.flat_map { |inner| owners_in(inner) }
        when Array then value.flat_map { |inner| owners_in(inner) }
        else []
        end
      end
      private :owners_in

      # The page of what was read, which Render gives as dashboardUrl, or of the thing the path reads inside. One deploy of
      # a service has its own page under the service's.
      DEPLOY_PATH = %r{\A/services/[^/]+/deploys/(?<deploy>[^/]+)\z}

      def read_link(path, answer, parent)
        deploy = path.match(DEPLOY_PATH)&.[](:deploy)
        url = if deploy && parent.is_a?(Hash) && parent["dashboardUrl"].present?
          "#{parent['dashboardUrl']}/deploys/#{Http.segment(deploy)}"
        else
          [ answer, parent ].find { |read| read.is_a?(Hash) && read["dashboardUrl"].present? }&.dig("dashboardUrl")
        end
        url && Telemetry::Link.new(provider: PROVIDER, url: url)
      end
      private :read_link

      # The workspace on the resource map: its services, sites, cron jobs and datastores, the repositories services build
      # from and the domains they serve. What could not be read for one service is a gap, not a failed sweep.
      def map_of(environment_row)
        map_of_scopes(environment_row, kinds: MAP_KINDS) { |pack| pack.map_of_workspace(environment_row) }
      end

      # What a sweep puts on the map for one workspace.
      MAP_KINDS = [ *SERVICE_KINDS, ResourceMap::KIND_DATABASE, ResourceMap::KIND_WORKFLOW, ResourceMap::KIND_DOMAIN, ResourceMap::KIND_REPOSITORY ].freeze

      def map_of_workspace(environment_row)
        api = api(environment_row)
        account = workspace_of(environment_row)
        reading = MapReading.new(account)
        gaps = []
        settings = {}
        services = api.services(account)
        bounded(services, "services", [ ResourceMap::KIND_SERVICE, ResourceMap::KIND_JOB, ResourceMap::KIND_SITE, ResourceMap::KIND_DOMAIN, ResourceMap::KIND_REPOSITORY ], gaps)
        services.items.each { |service| read_service(api, reading, service, settings, gaps) }
        [ [ POSTGRES, api.postgres_databases(account), "Postgres databases" ], [ KEY_VALUE, api.key_values(account), "Key Value instances" ] ].each do |type, stores, what|
          bounded(stores, what, [ ResourceMap::KIND_DATABASE ], gaps)
          stores.items.each { |store| reading.datastore(type, store) }
        end
        map_workflows(api, account, reading, gaps)
        groups = slowed?(gaps) ? {} : group_env(api, account, services.items.map { |service| service["id"] }, gaps)
        ResourceMap::Snapshot.new(resources: reading.resources, links: reading.links, gaps: gaps, uses: uses_of(environment_row, settings, groups))
      end

      # Only the service or datastore a change named, read again as the sweep reads it, with what its settings point at.
      # Render names either by data.serviceId (Integrations::MapEventSources::Render), and a datastore event says it is
      # one. Gone only when Render answers not found for it. nil for a scope Render cannot narrow to, which a sweep reads.
      def map_refresh(environment_row, scope)
        return unless scope.external_id && [ nil, *SERVICE_KINDS, ResourceMap::KIND_DATABASE ].include?(scope.kind)
        return workspace_holding(environment_row, scope)&.map_refresh(environment_row, scope) if every_scope?(environment_row)

        api = api(environment_row)
        account = workspace_of(environment_row)
        reading = MapReading.new(account)
        return refreshed_datastore(api, reading, account, scope.external_id) if scope.kind == ResourceMap::KIND_DATABASE

        service = begin
          api.service(scope.external_id)
        rescue RenderApi::NotFound
          return ResourceMap::Snapshot.new(resources: [], gone: SERVICE_KINDS.map { |kind| [ PROVIDER_KEY, account, kind, scope.external_id ] })
        end
        gaps = []
        settings = {}
        read_service(api, reading, service, settings, gaps)
        groups = slowed?(gaps) ? {} : group_env(api, account, [ service["id"] ], gaps)
        ResourceMap::Snapshot.new(resources: reading.resources, links: reading.links, gaps: gaps, uses: uses_of(environment_row, settings, groups))
      end

      # One service with its latest deploy, the domains it serves and its own settings, onto the reading. What could not be
      # read for it is a gap.
      def read_service(api, reading, service, settings, gaps)
        deploy = begin
          api.deploys(service["id"], limit: 1).first
        rescue Integrations::RateLimited
          raise
        rescue RenderApi::Error => error
          gaps << ResourceMap::Gap.new(text: Sentence.join("The latest deploy of #{service['name']} could not be read", error), kinds: [])
          nil
        end
        found = reading.service(service, deploy)
        settings[found] = service_env(api, service, gaps) unless slowed?(gaps)
        return unless [ WEB_SERVICE, STATIC_SITE ].include?(service["type"])

        begin
          domains = api.custom_domains(service["id"])
          bounded(domains, "custom domains of #{service['name']}", [ ResourceMap::KIND_DOMAIN ], gaps)
          domains.items.each { |domain| reading.domain(found, domain["name"]) }
        rescue Integrations::RateLimited
          raise
        rescue RenderApi::Error => error
          gaps << ResourceMap::Gap.new(text: Sentence.join("The custom domains of #{service['name']} could not be read", error), kinds: [ ResourceMap::KIND_DOMAIN ])
        end
      end
      private :read_service

      # The workspace's workflows with the repository each builds from. A list Render refuses is a gap that holds back no
      # other kind.
      def map_workflows(api, account, reading, gaps)
        workflows = api.workflows(account)
        bounded(workflows, "workflows", [ ResourceMap::KIND_WORKFLOW ], gaps)
        workflows.items.each { |workflow| reading.workflow(workflow) }
      rescue Integrations::RateLimited
        raise
      rescue RenderApi::Error => error
        gaps << ResourceMap::Gap.new(text: Sentence.join("The workflows could not be read", error), kinds: [ ResourceMap::KIND_WORKFLOW ])
      end
      private :map_workflows

      # A datastore is a Postgres database or a Key Value instance, and its id alone does not say which, so each is asked.
      def refreshed_datastore(api, reading, account, id)
        [ [ POSTGRES, :postgres ], [ KEY_VALUE, :key_value ] ].each do |type, read|
          reading.datastore(type, api.public_send(read, id))
          return ResourceMap::Snapshot.new(resources: reading.resources, links: reading.links)
        rescue RenderApi::NotFound
          next
        end
        ResourceMap::Snapshot.new(resources: [], gone: [ [ PROVIDER_KEY, account, ResourceMap::KIND_DATABASE, id ] ])
      end
      private :refreshed_datastore

      # Each service's own settings over those of the groups linked to it, as where they point.
      def uses_of(environment_row, settings, groups)
        workspace = environment_row.integration.workspace
        settings.flat_map do |key, own|
          ResourceMap::Use.read(from: key, workspace: workspace, values: groups.fetch(key.last, {}).merge(own.to_h))
        end
      end
      private :uses_of

      # A service's own variables, by name and value, read in memory only. Render's API answers every value as written,
      # so nothing is hidden by name. nil, with a settings gap, when they could not be read.
      def service_env(api, service, gaps)
        read = api.env_vars(service["id"])
        gaps << ResourceMap::Gap.new(text: "Only the first #{read.items.size} settings of #{service['name']} were read.", kinds: [], settings: true) if read.incomplete?
        read.items.to_h { |variable| [ variable["key"], variable["value"] ] }
      rescue Integrations::RateLimited
        gaps << ResourceMap::Gap.new(text: SLOWED, kinds: [], settings: true)
        nil
      rescue RenderApi::Error => error
        gaps << ResourceMap::Gap.new(text: Sentence.join("The settings of #{service['name']} could not be read", error), kinds: [], settings: true)
        nil
      end
      private :service_env

      # Being asked to slow down while reading settings stops reading them, and the map's own reads go on.
      SLOWED = "Render asked Firefight to slow down, so the rest of the services' settings were not read this time.".freeze

      def slowed?(gaps) = gaps.any? { |gap| gap.text == SLOWED }
      private :slowed?

      # The variables each service gets from the environment groups linked to it, by service id. A service's own
      # variable of the same name wins, as it does on Render (render.com/docs/configure-environment-variables).
      def group_env(api, account, service_ids, gaps)
        groups = api.env_groups(account)
        gaps << ResourceMap::Gap.new(text: "Only the first #{groups.size} environment groups were read.", kinds: [], settings: true) if groups.size >= RenderApi::PAGE_SIZE
        groups.select { |group| Array(group["serviceLinks"]).any? { |link| service_ids.include?(link["id"]) } }.each_with_object({}) do |group, by_service|
          values = Array(api.env_group(group["id"])["envVars"]).to_h { |variable| [ variable["key"], variable["value"] ] }
          Array(group["serviceLinks"]).each { |link| by_service[link["id"]] = by_service.fetch(link["id"], {}).merge(values) }
        end
      rescue Integrations::RateLimited
        gaps << ResourceMap::Gap.new(text: SLOWED, kinds: [], settings: true)
        {}
      rescue RenderApi::Error => error
        gaps << ResourceMap::Gap.new(text: Sentence.join("The environment groups could not be read", error), kinds: [], settings: true)
        {}
      end
      private :group_env

      # A list read only up to its bound is a gap, and what it holds is not taken as gone.
      def bounded(read, what, kinds, gaps)
        gaps << ResourceMap::Gap.new(text: "Only the first #{read.items.size} #{what} were read.", kinds: kinds) if read.incomplete?
      end
      private :bounded

      # What normal looks like for its services and datastores: a week of CPU, memory and, for a datastore, active
      # connections, one reading an hour, instances added up. A resource Render cannot read keeps yesterday's baselines,
      # and being asked to slow down stops the whole read.
      def baselines_of(environment_row, resources, window)
        return by_scope(environment_row, resources) { |pack, group| pack.baselines_of(environment_row, group, window) } if every_scope?(environment_row)

        api = api(environment_row)
        resources.flat_map do |resource|
          type = type_of(resource)
          next [] unless type

          BASELINE_METRICS.filter_map do |name|
            metric = METRICS.fetch(name)
            next unless metric.applies.include?(type)

            series = api.metrics(metric.path, "resource" => resource.external_id, "startTime" => window.begin.utc.iso8601,
                                              "endTime" => window.end.utc.iso8601, "resolutionSeconds" => BASELINE_RESOLUTION)
            baseline(resource, name, series)
          end
        rescue Integrations::RateLimited
          raise
        rescue RenderApi::Error => error
          Rails.logger.warn("baseline_sweep.resource_failed resource=#{resource.id} error=#{error.message}")
          []
        end
      end

      # Reads each workspace the connection reaches, so one the key can no longer read is said on the connection.
      def check_health!(environment_row)
        ConnectionSettings.of(environment_row).scopes.each { |workspace| api(environment_row).owner(workspace) }
      rescue RenderApi::Error => error
        fail! error.message
      end

      # Builds the snapshot for map_of, one resource at a time.
      class MapReading
        attr_reader :resources, :links

        def initialize(account)
          @account = account
          @resources = []
          @links = []
        end

        def service(service, deploy)
          details = service["serviceDetails"] || {}
          commit = deploy&.dig("commit", "id")
          found = add(service["type"], service, status: service["suspended"] == SUSPENDED ? SUSPENDED : deploy&.dig("status"),
                                                details: {
                                                  "type" => TYPE_WORDS[service["type"]], "plan" => details["plan"], "region" => details["region"],
                                                  ResourceMap::INSTANCES => details["numInstances"], "branch" => service["branch"],
                                                  ResourceMap::DEPLOYED_COMMIT => commit
                                                }.compact)
          repository(found, service["repo"])
          host = URI.parse(details["url"].to_s).host if details["url"].present?
          domain(found, host) if host.present?
          found
        rescue URI::InvalidURIError
          found
        end

        def datastore(type, store)
          add(type, store, status: store["status"],
                           details: { "type" => TYPE_WORDS[type], "plan" => store["plan"], "region" => store["region"],
                                      "engine" => ("Postgres #{store['version']}" if type == POSTGRES) }.compact)
        end

        def workflow(workflow)
          build = workflow["buildConfig"] || {}
          details = { "type" => TYPE_WORDS[WORKFLOW], "region" => workflow["region"], "branch" => build["branch"] }.compact
          page = format(WORKFLOW_PAGE, id: Http.segment(workflow["id"]))
          found = add(WORKFLOW, workflow.merge("dashboardUrl" => page), status: nil, details: details)
          repository(found, build["repo"])
          found
        end

        def domain(service, host)
          found = ResourceMap.domain(host)
          @resources << found
          @links << ResourceMap::FoundLink.new(from: found.key, to: service, relation: ResourceMap::RELATION_SERVED_BY)
        end

        private

        def add(type, row, status:, details:)
          found = ResourceMap::Found.new(provider: PROVIDER_KEY, account: @account, kind: KINDS.fetch(type, ResourceMap::KIND_SERVICE),
                                         external_id: row["id"].to_s, name: row["name"].presence || row["id"].to_s, status: status,
                                         url: row["dashboardUrl"], details: details)
          @resources << found
          found.key
        end

        # The repository a service builds from, on whichever code host the registry knows.
        def repository(from, url)
          found = ResourceMap.repository_of(url)
          return unless found

          @resources << found
          @links << ResourceMap::FoundLink.new(from: from, to: found.key, relation: ResourceMap::RELATION_BUILT_FROM)
        end
      end

      private

      def api(environment_row)
        key = ConnectionSettings.of(environment_row).credential(API_KEY)
        fail! "This environment has no Render API key. Reconnect it on the Integrations page." if key.blank?

        RenderApi.new(key)
      end

      def workspace_of(environment_row) = scope!(environment_row)

      # A listing of every workspace the connection reaches, each read by a pack of its own and headed with its own.
      def every_workspace(environment_row)
        texts = ConnectionSettings.of(environment_row).scopes.map do |workspace|
          Array(yield(scoped(workspace))["content"]).filter_map { |part| part["text"] }.join("\n")
        end
        Telemetry.result(texts.join("\n\n"), link: nil)
      end

      # The pack of the workspace a change is in. Render's payload names no workspace (render.com/docs/webhooks, Request
      # body), so it is the one the map has the service or datastore in, or else the one Render says owns it (a service's
      # ownerId, a datastore's owner, spec Service and PostgresDetail). nil, for a sweep to read, when neither says.
      def workspace_holding(environment_row, scope)
        reached = ConnectionSettings.of(environment_row).scopes
        on_map = Scopes.holding(environment_row, scope.external_id)
        owner = on_map.presence || workspace_owning(environment_row, scope)
        scoped(owner) if owner && reached.include?(owner)
      end

      def workspace_owning(environment_row, scope)
        api = api(environment_row)
        reads = scope.kind == ResourceMap::KIND_DATABASE ? %i[postgres key_value] : %i[service]
        reads.each do |read|
          found = api.public_send(read, scope.external_id)
          return found["ownerId"].presence || found.dig("owner", "id")
        rescue RenderApi::NotFound
          next
        end
        nil
      end

      def resources(environment_row)
        @resources ||= begin
          api = api(environment_row)
          workspace = workspace_of(environment_row)
          reads = [ api.services(workspace), api.postgres_databases(workspace), api.key_values(workspace), workflows_read(api, workspace) ]
          @resources_cut = reads.any?(&:incomplete?)
          reads[0].items.map { |service| service_entry(service) } + reads[1].items.map { |database| datastore_entry(database, POSTGRES) } +
            reads[2].items.map { |store| datastore_entry(store, KEY_VALUE) } + reads[3].items.map { |workflow| workflow_entry(workflow) }
        end
      end

      # The workspace's workflows. A list Render refuses or fails, such as on a workspace without workflows, is said beside
      # the rest rather than failing the listing, and being asked to slow down still stops the read.
      def workflows_read(api, workspace)
        api.workflows(workspace)
      rescue Integrations::RateLimited
        raise
      rescue RenderApi::Error => error
        @workflows_unread = error
        Pages::Read.new(items: [], complete: true)
      end

      def workflow_entry(workflow)
        { id: workflow["id"], name: workflow["name"], type: WORKFLOW, url: format(WORKFLOW_PAGE, id: Http.segment(workflow["id"])), status: nil }
      end

      def resources_cut?(environment_row)
        resources(environment_row)
        @resources_cut
      end

      def service_entry(service)
        { id: service["id"], name: service["name"], type: service["type"], url: service["dashboardUrl"],
          status: service["suspended"] == SUSPENDED ? "suspended by #{Array(service['suspenders']).join(', ').presence || 'Render'}" : "running" }
      end

      def datastore_entry(store, type) = { id: store["id"], name: store["name"], type: type, url: store["dashboardUrl"], status: store["status"].to_s }

      def find_resource(environment_row, asked)
        fail! "Say which service or datastore, by name or id. list_resources shows them." if asked.to_s.strip.empty?

        found = Named.find(resources(environment_row), asked, id: :id, name: :name, provider: PROVIDER, connection: environment_row)
        return found if found
        fail!("Nothing called #{asked} in this workspace. list_resources shows what there is.") unless resources_cut?(environment_row)

        resource_by_id(environment_row, asked.to_s.strip) ||
          fail!("Only the first #{resources(environment_row).size} services and datastores were read, and none in this workspace is called " \
                "#{asked}. Name it by its id, which Render shows on its page.")
      end

      # A service or datastore past the listing's cut, read by its id, and only when this workspace owns it.
      def resource_by_id(environment_row, id)
        api = api(environment_row)
        [ [ :service, ->(found) { service_entry(found) } ], [ :postgres, ->(found) { datastore_entry(found, POSTGRES) } ],
          [ :key_value, ->(found) { datastore_entry(found, KEY_VALUE) } ], [ :workflow, ->(found) { workflow_entry(found) } ] ].each do |read, entry|
          found = api.public_send(read, id)
          owner = found["ownerId"].presence || found.dig("owner", "id")
          return owner == workspace_of(environment_row) ? entry.call(found) : nil
        rescue RenderApi::NotFound
          next
        end
        nil
      end

      # The page Render gives each resource (dashboardUrl), the only address its API returns.
      def link(resource) = resource[:url].present? ? Telemetry::Link.new(provider: PROVIDER, url: resource[:url]) : nil

      # The Render type of a map resource, from its kind and what the sweep wrote.
      def type_of(resource)
        return KEY_VALUE if resource.details.to_h["type"] == TYPE_WORDS[KEY_VALUE]
        return POSTGRES if resource.kind == ResourceMap::KIND_DATABASE

        TYPE_WORDS.key(resource.details.to_h["type"]) || (WEB_SERVICE if resource.kind == ResourceMap::KIND_SERVICE)
      end

      def chart(environment_row, resource, name, started, ended, resolution)
        metric = METRICS.fetch(name)
        query = { "resource" => resource[:id], "startTime" => started.utc.iso8601, "endTime" => ended.utc.iso8601,
                  "resolutionSeconds" => (resolution if metric.resolution) }.compact.merge(metric.query)
        series = api(environment_row).metrics(metric.path, query)
        series = status_class(series, STATUS_CLASSES[name]) if STATUS_CLASSES.key?(name)
        unit = series.filter_map { |each| each["unit"].presence }.first || "count"
        drawn = series.map do |each|
          Telemetry::Series.new(label: series_label(each, resource), points: points(each))
        end
        Telemetry::Chart.new(title: "#{metric.title} of #{resource[:name]}", unit: unit, series: drawn, from: started, to: ended, link: resource[:url])
      end

      # One series adding up every status code of the class, such as 500, 502 and 503 for 5xx.
      def status_class(series, digit)
        matching = series.select { |each| status_code(each).to_s.start_with?(digit) }
        summed = matching.flat_map { |each| points(each) }.group_by(&:first).map { |at, pairs| [ at, pairs.sum(&:last) ] }.sort_by(&:first)
        [ { "labels" => [ { "field" => "statusCode", "value" => "#{digit}xx" } ], "unit" => matching.first&.dig("unit"),
            "values" => summed.map { |at, value| { "timestamp" => at.utc.iso8601, "value" => value } } } ]
      end

      # The spec does not name the label a status code comes under, so it is the label whose value is one.
      def status_code(series) = Array(series["labels"]).map { |label| label["value"].to_s }.find { |value| value.match?(STATUS_CODE) }

      def series_label(series, resource)
        labels = Array(series["labels"]).reject { |label| [ "resource", "service" ].include?(label["field"]) }
        labels.map { |label| label["value"] }.compact.join(" ").presence || resource[:name]
      end

      def points(series)
        Array(series["values"]).filter_map do |point|
          at = Telemetry.parse_time(point["timestamp"])
          [ at, point["value"].to_f ] if at && !point["value"].nil?
        end
      end

      # Instances added up at each reading, so a service reads as a whole.
      def baseline(resource, name, series)
        readings = series.flat_map { |each| points(each) }.group_by(&:first).map { |at, pairs| [ at, pairs.sum(&:last) ] }.sort_by(&:first)
        return nil if readings.empty?

        unit = series.filter_map { |each| each["unit"].presence }.first
        ResourceMap::Baseline::Found.new(key: resource.key, metric: name, label: METRICS.fetch(name).title, unit: unit, points: readings)
      end

      def service_lines(environment_row, resource)
        service = api(environment_row).service(resource[:id])
        details = service["serviceDetails"] || {}
        autoscaling = details["autoscaling"] || {}
        commands = details["envSpecificDetails"] || {}
        latest = api(environment_row).deploys(resource[:id], limit: 1).first
        [
          "#{resource[:name]}, #{TYPE_WORDS.fetch(service['type'], service['type'])}, #{resource[:status]}",
          ([ ("plan #{details['plan']}" if details["plan"]), ("region #{details['region']}" if details["region"]),
             ("runtime #{details['runtime']}" if details["runtime"]) ].compact.join(", ").presence),
          scaling_line(details, autoscaling),
          (running_line(environment_row, resource) if SCALABLE.include?(service["type"])),
          ("Schedule: #{details['schedule']}, last succeeded #{details['lastSuccessfulRunAt'] || 'never'}" if details["schedule"]),
          source_line(service, commands),
          ("Address: #{details['url']}" if details["url"].present?),
          ("Health check path: #{details['healthCheckPath'].presence || 'none, so Render only checks that a port is open'}" if service["type"] == WEB_SERVICE),
          ("Disk: #{details.dig('disk', 'sizeGB')} GB at #{details.dig('disk', 'mountPath')}" if details["disk"]),
          ("Latest deploy: #{deploy_line(resource, latest)}" if latest),
          recent_events(environment_row, resource)
        ]
      end

      def scaling_line(details, autoscaling)
        if autoscaling["enabled"]
          criteria = %w[cpu memory].filter_map { |name| "#{name} #{autoscaling.dig('criteria', name, 'percentage')}%" if autoscaling.dig("criteria", name, "enabled") }
          return "Autoscaling between #{autoscaling['min']} and #{autoscaling['max']} instances on #{criteria.join(' and ').presence || 'no criteria'}"
        end
        "Instances: #{details['numInstances']}" if details.key?("numInstances")
      end

      # The instances running now, each by its id and when it started, which is what search_logs names a line by.
      def running_line(environment_row, resource)
        running = api(environment_row).instances(resource[:id]).sort_by { |instance| instance["createdAt"].to_s }
        return "Instances running now: none" if running.empty?

        "Instances running now, #{running.size}: #{running.map { |instance| "#{instance['id']} since #{instance['createdAt']}" }.join(', ')}"
      rescue Integrations::RateLimited
        raise
      rescue RenderApi::Error => error
        Sentence.join("The instances running now could not be read", error)
      end

      # A workflow as Render's API describes it (spec, GET /workflows/{workflowId}), with its tasks.
      def workflow_lines(environment_row, resource)
        api = api(environment_row)
        workflow = api.workflow(resource[:id])
        build = workflow["buildConfig"] || {}
        tasks = begin
          api.tasks(resource[:id]).items.filter_map { |task| task["name"] }
        rescue Integrations::RateLimited
          raise
        rescue RenderApi::Error => error
          error
        end
        [
          "#{resource[:name]}, workflow#{", region #{workflow['region']}" if workflow['region']}#{", runtime #{build['runtime']}" if build['runtime']}",
          ("Builds #{build['repo']}#{", branch #{build['branch']}" if build['branch']}#{", in #{build['rootDir']}" if build['rootDir'].present?}" if build["repo"]),
          ("Run command: #{workflow['runCommand']}" if workflow["runCommand"].present?),
          ("Autodeploy: #{workflow['autoDeployTrigger']}" if workflow["autoDeployTrigger"]),
          (tasks.is_a?(Exception) ? Sentence.join("Its tasks could not be read", tasks) : "Tasks: #{tasks.join(', ').presence || 'none yet'}"),
          "run_history reads how its runs went."
        ]
      end

      def source_line(service, commands)
        what = service["repo"] ? "Runs #{service['repo']}#{", branch #{service['branch']}" if service['branch']}" : ("Runs the image #{service['imagePath']}" if service["imagePath"])
        start = commands["startCommand"] || commands["dockerCommand"]
        [ what, ("start command #{start}" if start.present?) ].compact.join(", ").presence
      end

      def recent_events(environment_row, resource)
        events = api(environment_row).events(resource[:id], "startTime" => EVENT_MINUTES.minutes.ago.utc.iso8601, "limit" => RECENT_EVENTS)
        return "Events in the last day: none" if events.empty?

        "Events in the last day, newest first:\n#{events.map { |event| event_line(event) }.join("\n")}"
      rescue Integrations::RateLimited
        raise
      rescue RenderApi::Error => error
        Sentence.join("Events could not be read", error)
      end

      def postgres_lines(environment_row, resource)
        database = api(environment_row).postgres(resource[:id])
        maintenance = database["maintenance"]
        [
          "#{resource[:name]}, Postgres #{database['version']}, status #{database['status']}",
          "Plan #{database['plan']}, region #{database['region']}, disk #{database['diskSizeGB'] || 'unknown'} GB" \
            "#{', grows on its own' if database['diskAutoscalingEnabled']}",
          "High availability #{database['highAvailabilityEnabled'] ? 'on' : 'off'}, role #{database['role']}, " \
            "#{Array(database['readReplicas']).size} read replicas, connection pooling #{database['connectionPool'] || 'none'}",
          ("Suspended by #{Array(database['suspenders']).join(', ')}" if database["suspended"] == SUSPENDED),
          ("Maintenance: #{maintenance['type']} #{maintenance['state']}, scheduled #{maintenance['scheduledAt']}" if maintenance)
        ]
      end

      def key_value_lines(environment_row, resource)
        store = api(environment_row).key_value(resource[:id])
        maintenance = store["maintenance"]
        [
          "#{resource[:name]}, Key Value #{store['version']}, status #{store['status']}",
          "Plan #{store['plan']}, region #{store['region']}",
          ("Eviction policy #{store.dig('options', 'maxmemoryPolicy')}, persistence #{store.dig('options', 'persistenceMode')}" if store["options"]),
          ("Maintenance: #{maintenance['type']} #{maintenance['state']}, scheduled #{maintenance['scheduledAt']}" if maintenance)
        ]
      end

      # A deploy's page, as Render's own CLI writes it (render-oss/cli, pkg/dashboard/dashboard.go).
      def deploy_line(resource, deploy)
        commit = deploy["commit"]
        what = if commit then "#{commit['id'].to_s.first(12)} \"#{commit['message'].to_s.lines.first.to_s.strip}\""
        elsif deploy["image"] then "image #{deploy.dig('image', 'ref')}"
        end
        page = "#{resource[:url]}/deploys/#{deploy['id']}" if resource[:url].present?
        [ deploy["createdAt"], "deploy #{deploy['id']}", deploy["status"], what, ("triggered by #{deploy['trigger'].to_s.tr('_', ' ')}" if deploy["trigger"]),
          ("finished #{deploy['finishedAt']}" if deploy["finishedAt"]), ("page #{page}" if page) ].compact.join(", ")
      end

      def event_line(event)
        details = event["details"] || {}
        said = [ details["deployStatus"], details["buildStatus"], details["status"].is_a?(String) ? details["status"] : nil,
                 ("from #{details['fromInstances']} to #{details['toInstances']} instances" if details.key?("toInstances")),
                 ("disk #{details['diskName']} at #{details['usagePercent']}%" if details["usagePercent"]),
                 failure_words(details["reason"].is_a?(Hash) && details["reason"].key?("failure") ? details.dig("reason", "failure") : details["reason"]),
                 details["message"] ].compact.join(", ")
        "#{event['timestamp']} #{event['type'].to_s.tr('_', ' ')}#{": #{said}" if said.present?}"
      end

      # Render's FailureReason (spec, schema failureReason) in words.
      def failure_words(reason)
        return nil unless reason.is_a?(Hash)

        [ ("ran out of memory, limit #{reason.dig('oomKilled', 'memoryLimit')}" if reason["oomKilled"]),
          ("exited with code #{reason['nonZeroExit']}" if reason["nonZeroExit"]),
          ("exited without being asked to stop" if reason["earlyExit"]),
          ("failed its health check: #{reason['unhealthy']}" if reason["unhealthy"].present?),
          ("timed out after #{reason['timedOutSeconds']} seconds#{": #{reason['timedOutReason']}" if reason['timedOutReason'].present?}" if reason["timedOutSeconds"]),
          ("evicted#{": #{reason['evictionReason']}" if reason['evictionReason'].present?}" if reason["evicted"]) ].compact.join(", ").presence
      end
    end
  end
end
