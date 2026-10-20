module Integrations
  module Packs
    # Railway for one environment in each project a connection reads, one, several or every one its token can read (the
    # project connect field, a scope). It reads their services, databases and cron jobs, and their logs, metrics,
    # traces, deployments and cron runs, with an account or workspace token. A call may name another environment of
    # the same project, such as a PR environment, which only that call reads. Every tool reads, except the restart,
    # rollback and scale Halon uses to apply fixes and the deployment changes in Deployments. Queries and mutations are
    # the ones the Railway CLI sends (railwayapp/cli, src/gql) or Railway's API docs give (railwayapp/docs,
    # content/docs/integrations/api).
    class Railway < NativePack
      # The environment row's credentials, which only this pack reads.
      API_TOKEN = "api_token".freeze
      PROJECT = "project".freeze
      ENVIRONMENT = "environment".freeze

      PROVIDER = "Railway".freeze
      PROVIDER_KEY = "railway".freeze
      # Railway builds from GitHub repositories and names one as owner/name (schema, ServiceSource.repo), so the code
      # host's own registry entry gives its address.
      REPOSITORY_HOST = "github".freeze

      # How the CLI tells a service instance apart (railwayapp/cli, src/resources.rs): a cron schedule makes a cron job,
      # and an image naming a database engine makes a database.
      SERVICE = "service".freeze
      DATABASE = "database".freeze
      CRON_JOB = "cron job".freeze
      KINDS = { SERVICE => ResourceMap::KIND_SERVICE, DATABASE => ResourceMap::KIND_DATABASE, CRON_JOB => ResourceMap::KIND_JOB }.freeze
      ENGINES = {
        "Postgres" => %w[postgres postgis timescale], "Redis" => %w[redis valkey], "MongoDB" => %w[mongo], "MySQL" => %w[mysql mariadb],
        "Memcached" => %w[memcached]
      }.freeze

      # Railway's three kinds of logs (docs, content/docs/observability/logs.md): what a deployment prints, its build,
      # and the HTTP requests reaching it through a public domain.
      APP = "app".freeze
      BUILD = "build".freeze
      HTTP = "http".freeze
      LOG_TYPES = [ APP, BUILD, HTTP ].freeze
      # The API answers at most 5000 lines a call (schema, deploymentLogs), and this many reads well.
      LOG_LIMIT = 200
      DEPLOYMENT_LIMIT = 20
      ROLLBACK_LOOKUP = 50

      # Each metric a tool takes, in the names every capability uses, and the measurement that answers it (schema, enum
      # MetricMeasurement). CPU is in vCPU, as the CLI labels it (src/commands/metrics.rs).
      MEASUREMENTS = {
        "cpu" => [ "CPU_USAGE", "CPU", "vCPU" ], "memory" => [ "MEMORY_USAGE_GB", "Memory", "GB" ],
        "network_in" => [ "NETWORK_RX_GB", "Network in", "GB" ], "network_out" => [ "NETWORK_TX_GB", "Network out", "GB" ],
        "disk" => [ "DISK_USAGE_GB", "Disk usage", "GB" ]
      }.freeze
      # Request counts by status code come from Railway's edge, so only for traffic through a public domain (docs,
      # content/docs/observability/metrics.md).
      HTTP_METRICS = { "requests" => [ "Requests", nil ], "http_4xx" => [ "4xx responses", "4" ], "http_5xx" => [ "5xx responses", "5" ] }.freeze
      # How long those requests took, each a percentile Railway keeps in milliseconds (schema, HttpDurationMetricsSample).
      LATENCY_METRICS = {
        "latency_p50" => [ "p50", "Latency, median" ], "latency_p95" => [ "p95", "Latency, 95th percentile" ],
        "latency_p99" => [ "p99", "Latency, 99th percentile" ]
      }.freeze
      MILLISECONDS = "ms".freeze
      METRICS = (MEASUREMENTS.keys + HTTP_METRICS.keys + LATENCY_METRICS.keys).freeze
      DEFAULT_METRICS = %w[cpu memory requests http_5xx].freeze
      DATABASE_METRICS = %w[cpu memory disk].freeze
      BASELINE_METRICS = %w[cpu memory].freeze
      PER_MINUTE = "per minute".freeze
      # A reading at least every minute, and about this many points over the range.
      MIN_SAMPLE = 60
      POINTS = 60
      BASELINE_SAMPLE = 3600
      # The CLI's own cap on replicas across regions (src/controllers/regions.rs, validate_total_replicas).
      MAX_REPLICAS = 50

      RESOURCE = { "type" => "string", "description" => "A service, database or cron job in the environment, by name or id, as list_resources shows it" }.freeze
      DEPLOYMENT = { "type" => "string", "description" => "A deployment id, as list_deployments shows it (optional, the latest)" }.freeze
      # Another environment of the project a call reads instead of the connection's own, such as a PR environment.
      ENVIRONMENT_PARAM = {
        "type" => "string",
        "description" => "Another environment of the project, such as a PR environment, by name or id as list_resources lists them (optional, the connection's own)"
      }.freeze

      tool :list_resources,
           summary: "Lists the services, databases and cron jobs in the Railway environment.",
           description: "The services, databases and cron jobs in the Railway project environment for this connection, with " \
                        "the status of each one's latest deployment, and the project's other environments, PR environments with " \
                        "their pull request. Use it first to find the name to pass to the other tools, and an environment to pass as environment",
           params_schema: { "type" => "object", "properties" => { "environment" => ENVIRONMENT_PARAM } },
           read_only: true

      tool :describe_resource,
           summary: "Shows how one service, database or cron job is set up and how it stands now.",
           description: "How one service, database or cron job is set up and how it stands now: its latest deployment and the " \
                        "state of each replica, its replicas and region, what it runs, its start command, health check, restart " \
                        "policy, whether it sleeps when idle, its schedule and its domains",
           params_schema: { "type" => "object", "properties" => { "resource" => RESOURCE, "environment" => ENVIRONMENT_PARAM }, "required" => [ "resource" ] },
           read_only: true

      tool :search_logs,
           summary: "Searches app, build or request logs of one service.",
           description: "Log lines from one service, newest first, at most #{LOG_LIMIT}. type app is what the code prints, across " \
                        "its deployments in the range, or one deployment's when deployment is given. build is one deployment's " \
                        "build. http is the requests reaching one " \
                        "deployment through a public domain, with status and duration. Filter by text, or leave lines out with exclude",
           params_schema: {
             "type" => "object",
             "properties" => {
               "resource" => RESOURCE,
               "environment" => ENVIRONMENT_PARAM,
               "type" => { "type" => "string", "enum" => LOG_TYPES, "description" => "Which logs (optional, app)" },
               "deployment" => DEPLOYMENT,
               "text" => { "type" => "string", "description" => "Only lines containing this text (optional)" },
               "exclude" => { "type" => "string", "description" => "Leave out lines containing this text (optional)" },
               "limit" => { "type" => "integer", "description" => "At most this many lines (optional, #{LOG_LIMIT})" },
               **Capabilities::RANGE
             },
             "required" => [ "resource" ]
           },
           read_only: true

      tool :query_metrics,
           summary: "Shows CPU, memory, network, request and latency metrics of a service or database.",
           description: "Metrics of one service or database over time: CPU, memory, network in and out and disk, and requests, " \
                        "4xx and 5xx responses and the median, 95th and 99th percentile latency through its public domains. " \
                        "Returns min, average, max and latest, and the person sees each metric as a chart",
           params_schema: {
             "type" => "object",
             "properties" => {
               "resource" => RESOURCE,
               "environment" => ENVIRONMENT_PARAM,
               "metrics" => { "type" => "array", "items" => { "type" => "string", "enum" => METRICS },
                              "description" => "Which metrics (optional, the usual ones for the resource)" },
               **Capabilities::RANGE
             },
             "required" => [ "resource" ]
           },
           read_only: true

      tool :list_deployments,
           summary: "Lists a service's deployments with status, commit and who started each.",
           description: "A service's deployments, newest first: when, the status (SUCCESS, FAILED, CRASHED, REMOVED and the " \
                        "rest), the commit, who started it, and whether Railway can still roll back to it. The id is what " \
                        "rollback_deployment takes. Use it to see what changed before something broke",
           params_schema: {
             "type" => "object",
             "properties" => {
               "resource" => RESOURCE,
               "environment" => ENVIRONMENT_PARAM,
               "limit" => { "type" => "integer", "description" => "At most this many deployments (optional, #{DEPLOYMENT_LIMIT})" }
             },
             "required" => [ "resource" ]
           },
           read_only: true

      tool :deploy_history,
           summary: "Shows a service's recent deployments with how long each took to go live.",
           description: "A service's recent deployments, each a build and its release, with its status, when it started and when " \
                        "it went live or failed and how long that took, and how long finished ones usually take. A deployment " \
                        "replaced since shows no length, since Railway keeps only when its status last changed",
           params_schema: {
             "type" => "object",
             "properties" => {
               "resource" => RESOURCE,
               "environment" => ENVIRONMENT_PARAM,
               "name" => { "type" => "string", "description" => "Only runs of this kind, deploy (optional)" },
               "run" => { "type" => "string", "description" => "Only this deployment, by its id, with each step it went through and how each ended (optional)" },
               "limit" => { "type" => "integer", "description" => "At most this many deployments (optional, #{DEPLOYMENT_LIMIT})" }
             },
             "required" => [ "resource" ]
           },
           read_only: true

      tool :restart_deployment,
           summary: "Restarts a service's latest deployment without building again.",
           description: "Restart the containers of a service's latest deployment without building it again, such as one that " \
                        "crashed and ran out of restarts",
           params_schema: { "type" => "object", "properties" => { "resource" => RESOURCE }, "required" => [ "resource" ] },
           read_only: false

      tool :rollback_deployment,
           summary: "Rolls a service back to an earlier deployment.",
           description: "Put a service back on an earlier deployment, by the id list_deployments shows. Railway restores that " \
                        "deployment's image and variables without building, while it still keeps the image",
           params_schema: {
             "type" => "object",
             "properties" => {
               "resource" => RESOURCE,
               "deployment" => { "type" => "string", "description" => "The deployment to go back to, by its id" }
             },
             "required" => %w[resource deployment]
           },
           read_only: false

      tool :scale_service,
           summary: "Sets how many replicas a service runs, region by region.",
           description: "Set how many replicas a service runs in one of its regions, at most #{MAX_REPLICAS} across every region. " \
                        "A service in one region takes the count alone. A service in several regions takes the region too, as " \
                        "describe_resource names its regions, and the others keep their replicas. A region of several may go to " \
                        "0 while another still runs replicas",
           params_schema: {
             "type" => "object",
             "properties" => {
               "resource" => RESOURCE,
               "instances" => { "type" => "integer", "description" => "How many replicas to run in the region" },
               "region" => { "type" => "string", "description" => "The region to scale, by the id describe_resource shows, such as us-west2 (optional for a service in one region)" }
             },
             "required" => %w[resource instances]
           },
           read_only: false

      tool :api_read,
           summary: "Reads other Railway data such as environments, volumes and domains.",
           description: "Anything else Railway's API reads that the other tools do not cover, such as a project's environments " \
                        "and services, a deployment by its id, volumes and their backups, domains, TCP proxies, deployment " \
                        "triggers or the workspace's members. One GraphQL query to Railway's public API " \
                        "(#{RailwayApi::ENDPOINT}), written with the fields and arguments the API reference the railway_api " \
                        "skill names lists, or the key query fields it lists. A list is a connection: pass first, and the pageInfo's endCursor as after for the " \
                        "next page. Only reads, so a mutation or a subscription is refused. A query that reads variables, " \
                        "an environment's config or tokens comes back as names only",
           params_schema: {
             "type" => "object",
             "properties" => {
               "query" => { "type" => "string", "description" => "The GraphQL query, such as query($id: String!) { project(id: $id) { name environments { edges { node { id name } } } } }" },
               "variables" => { "type" => "object", "description" => "The query's variables by name, such as {\"id\": \"<project id>\"} (optional)" }
             },
             "required" => %w[query]
           },
           read_only: true

      include Deployments
      include CronRuns
      include Traces

      def self.credential_fields
        [
          CredentialField.new(key: API_TOKEN, label: "API token", secret: true, placeholder: "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
                              hint: "A workspace token for the project's workspace, created under Account Settings, Tokens, which the team shares rather than one person's account. " \
                                    "An account token works too. Firefight does not accept a project token, since it cannot apply fixes.")
        ]
      end

      # Reads each project chosen with the token and finds the environment in it, or for every project the token can
      # read, finds the environment in at least one, so a wrong token, project or environment is said on the form before
      # anything is saved.
      def self.credential_refusal(values, region: nil, fields: {})
        token = values[API_TOKEN].to_s.strip
        projects = Array(fields[PROJECT]).map { |each| each.to_s.strip }.compact_blank
        environment = fields[ENVIRONMENT].to_s.strip
        return "Paste an API token." if token.empty?
        return "Choose at least one project, or all the token can read." if projects.empty?
        return "Enter the environment, by its name or id." if environment.empty?

        api = RailwayApi.new(token)
        if projects == [ IntegrationProvider::ConnectField::ALL ]
          listed = scope_options(values).map(&:value)
          return "This token can read no Railway projects." if listed.empty?
          return nil if listed.any? { |project| environment_in(api.project(project), environment, quiet: true) }

          return "None of the projects this token can read has an environment called #{environment}."
        end
        projects.each { |project| environment_in(api.project(project), environment) }
        nil
      rescue RailwayApi::Error => error
        Sentence.join("Railway refused this token or project", error.message.delete_prefix("Railway refused this: "))
      rescue NativePack::Error => error
        error.message
      end

      # The projects the token can read, every workspace's an account token belongs to, or a workspace token's own
      # (Integrations::RailwayApi, projects), each named with its workspace when there are several.
      def self.scope_options(values, region: nil, fields: {})
        token = values.to_h.stringify_keys[API_TOKEN].to_s.strip
        raise NativePack::Error, "Paste an API token first." if token.empty?

        api = RailwayApi.new(token)
        workspaces = begin
          api.workspaces
        rescue RailwayApi::Refused
          []
        end
        listed = workspaces.empty? ? [ [ nil, api.projects.items ] ] : workspaces.map { |workspace| [ workspace, api.projects(workspace["id"]).items ] }
        listed.flat_map do |workspace, projects|
          projects.map do |project|
            name = project["name"].presence || project["id"].to_s
            IntegrationProvider::ConnectOption.new(value: project["id"].to_s, label: workspaces.many? ? "#{workspace['name']}, #{name}" : name)
          end
        end.uniq(&:value)
      rescue RailwayApi::Error => error
        raise NativePack::Error, Sentence.join("Railway did not list this token's projects", error.message.delete_prefix("Railway refused this: "))
      end

      def self.store_credentials!(environment_row, values)
        environment_row.store_credential!(API_TOKEN, values[API_TOKEN].to_s.strip)
      end

      # The project's environment named by its id or name, or a refusal that lists the ones there are. quiet answers nil
      # instead of refusing.
      def self.environment_in(project, asked, quiet: false)
        environments = Array(project&.dig("environments", "edges")).filter_map { |edge| edge["node"] }
        rows = environments.map { |each| { id: each["id"], name: each["name"], environment: each } }
        found = Named.find(rows, asked, id: :id, name: :name, provider: PROVIDER)&.dig(:environment)
        return found if found || quiet

        raise NativePack::Error, "Project #{project&.dig('name') || project&.dig('id')} has no environment called #{asked}. It has " \
                                 "#{environments.map { |each| each['name'] }.join(', ').presence || 'none'}."
      end

      # A read naming another environment of the project, such as a PR environment, reads that one alone. A change acts
      # only in the connection's own environment, since what a person may change is granted per connection and so per
      # environment, and naming another is refused as Firefight's rule.
      def call(tool_name, environment_row:, arguments:)
        @asked_environment = arguments[ENVIRONMENT].to_s.strip.presence
        @changing = tool_definitions.find { |definition| definition.name == tool_name }&.read_only == false
        super
      end

      def scoped(scope)
        super.tap do |pack|
          pack.instance_variable_set(:@asked_environment, @asked_environment)
          pack.instance_variable_set(:@changing, @changing)
        end
      end

      def list_resources(environment_row:, arguments:)
        return every_project(environment_row) { |pack| pack.list_resources(environment_row: environment_row, arguments: arguments) } if every_scope?(environment_row)

        rows = resources(environment_row).map do |resource|
          latest = resource[:instance]["latestDeployment"]
          "#{resource[:name]} (#{resource[:id]}), #{resource[:type]}, #{latest ? latest['status'].to_s.downcase : 'never deployed'}"
        end
        where = "the #{environment(environment_row)['name']} environment#{" of project #{scope_label(environment_row)}" if ConnectionSettings.of(environment_row).several_scopes?}"
        cut = " Only the first #{rows.size} were read, so name a resource by its id to reach the rest." if instances(environment_row).incomplete?
        text = rows.empty? ? "#{where.upcase_first} has no services." : "#{rows.size} services in #{where}.#{cut}\n#{rows.join("\n")}"
        Telemetry.result([ text, other_environments(environment_row) ].compact.join("\n"), link: project_link(environment_row))
      end

      def describe_resource(environment_row:, arguments:)
        resource = find_resource(environment_row, arguments["resource"])
        Telemetry.result(status_lines(resource).compact.join("\n"), link: link(environment_row, resource))
      end

      def search_logs(environment_row:, arguments:)
        resource = find_resource(environment_row, arguments["resource"])
        type = arguments["type"].presence || APP
        fail! "type must be one of #{LOG_TYPES.join(', ')}." unless LOG_TYPES.include?(type)

        started, ended = Capabilities::Answers.range(arguments)
        limit = Capabilities::Answers.limit(arguments, LOG_LIMIT)
        lines = case type
        when APP then app_logs(environment_row, resource, started, ended, limit, arguments)
        when BUILD then build_logs(environment_row, resource, started, ended, limit, arguments)
        else http_logs(environment_row, resource, started, ended, limit, arguments)
        end
        lines = lines.sort_by(&:at).reverse.first(limit)
        asked = "the #{type} logs of #{resource[:name]} from #{started.utc.iso8601} to #{ended.utc.iso8601}"
        Telemetry.result(Telemetry.logs_text(lines, asked: asked, limit: limit), link: link(environment_row, resource))
      end

      def query_metrics(environment_row:, arguments:)
        resource = find_resource(environment_row, arguments["resource"])
        started, ended = Capabilities::Answers.range(arguments)
        asked = Array(arguments["metrics"]).map(&:to_s) & METRICS
        asked = (resource[:type] == DATABASE ? DATABASE_METRICS : DEFAULT_METRICS) if asked.empty?
        sample = [ ((ended - started) / POINTS).ceil, MIN_SAMPLE ].max
        page = link(environment_row, resource)
        charts = measurement_charts(environment_row, resource, asked & MEASUREMENTS.keys, started, ended, sample, page) +
                 http_charts(environment_row, resource, asked & HTTP_METRICS.keys, started, ended, sample, page) +
                 latency_charts(environment_row, resource, asked & LATENCY_METRICS.keys, started, ended, sample, page)
        Telemetry.result("#{resource[:name]}\n#{Telemetry.charts_text(charts)}", charts: charts, link: page)
      end

      def list_deployments(environment_row:, arguments:)
        resource = find_resource(environment_row, arguments["resource"])
        deployments = api(environment_row).deployments(project_of(environment_row), environment(environment_row)["id"], resource[:id],
                                                       limit: Capabilities::Answers.limit(arguments, DEPLOYMENT_LIMIT))
        page = link(environment_row, resource)
        return Telemetry.result("#{resource[:name]} has no deployments.", link: page) if deployments.empty?

        rows = deployments.map { |deployment| deployment_line(deployment) }
        result = Telemetry.result("Latest #{rows.size} deployments of #{resource[:name]}, newest first. rollback_deployment takes an id " \
                                  "Railway can still roll back to.\n#{rows.join("\n")}", link: page)
        Capabilities::Deploys.with_deploys(result, deployments.map { |deployment| deploy_of(deployment) })
      end

      # The deployment serving now, asleep until a request wakes it, and one that was replaced. Railway says neither of a
      # deployment in any other state.
      DEPLOYMENT_LIVE = { "SUCCESS" => true, "SLEEPING" => true, "REMOVING" => false, "REMOVED" => false }.freeze

      def deploy_of(deployment)
        meta = deployment["meta"].is_a?(Hash) ? deployment["meta"] : {}
        status = status_of(deployment)
        Capabilities::Deploys::Deploy.new(
          id: deployment["id"], commit: meta["commitHash"], branch: meta["branch"],
          status: status, live: DEPLOYMENT_LIVE[deployment["status"].to_s],
          started_at: deployment["createdAt"], finished_at: ended_at(deployment, status)&.utc&.iso8601
        )
      end
      private :deploy_of

      # Railway's DeploymentStatus in Firefight's words. A deployment that slept had gone live, and one that crashed went
      # live and then failed. A removed one is read by status_of, since Railway removes both a deployment that was
      # replaced and one cancelled before it went live.
      DEPLOYMENT_STATUSES = {
        "initializing" => Capabilities::History::QUEUED, "queued" => Capabilities::History::QUEUED, "waiting" => Capabilities::History::QUEUED,
        "needs_approval" => Capabilities::History::QUEUED, "building" => Capabilities::History::RUNNING,
        "deploying" => Capabilities::History::RUNNING, "success" => Capabilities::History::SUCCEEDED,
        "sleeping" => Capabilities::History::SUCCEEDED, "failed" => Capabilities::History::FAILED, "crashed" => Capabilities::History::FAILED,
        "skipped" => Capabilities::History::CANCELLED
      }.freeze
      REMOVED_STATUSES = %w[REMOVED REMOVING].freeze
      # Railway keeps when a deployment's status last changed (statusUpdatedAt, or updatedAt before it kept that), which is
      # when it went live, failed, crashed or was skipped only while that is still its status. A removed deployment that
      # never went live ended when it was removed, and one that was replaced went live at a time Railway no longer keeps.
      ENDED_AT = %w[SUCCESS FAILED CRASHED SKIPPED].freeze
      # The steps a deployment takes once it passed its healthcheck, switching traffic to it and draining the old instances
      # (schema, enum DeploymentEventStep), so one that completed either went live.
      LIVE_STEPS = %w[CONFIGURE_NETWORK DRAIN_INSTANCES].freeze

      # A removed deployment went live when Railway can still roll back to it, which it offers only for one that served
      # (docs, content/docs/deployments/deployment-actions.md, Rollback), or when its steps say it took traffic. Otherwise
      # it was cancelled before it went live.
      def status_of(deployment, events: nil)
        word = deployment["status"].to_s
        return Capabilities::History.status(word, DEPLOYMENT_STATUSES) unless REMOVED_STATUSES.include?(word)

        went_live = deployment["canRollback"] == true || Array(events).any? do |event|
          LIVE_STEPS.include?(event["step"]) && event["completedAt"].present? && event.dig("payload", "error").blank?
        end
        went_live ? Capabilities::History::SUCCEEDED : Capabilities::History::CANCELLED
      end
      private :status_of

      def ended_at(deployment, status)
        word = deployment["status"].to_s
        ended = ENDED_AT.include?(word) || (REMOVED_STATUSES.include?(word) && status == Capabilities::History::CANCELLED)
        Telemetry.parse_time(deployment["statusUpdatedAt"].presence || deployment["updatedAt"]) if ended
      end
      private :ended_at

      def deploy_history(environment_row:, arguments:)
        resource = find_resource(environment_row, arguments["resource"])
        return one_deployment(environment_row, resource, arguments["run"]) if arguments["run"].present?

        deployments = api(environment_row).deployments(project_of(environment_row), environment(environment_row)["id"], resource[:id],
                                                       limit: Capabilities::Answers.limit(arguments, DEPLOYMENT_LIMIT))
        runs = deployments.map { |deployment| deployment_run(deployment) }
        Capabilities::History.result(runs, what: resource[:name], link: link(environment_row, resource), name: arguments["name"])
      end

      # The steps of a deployment (schema, enum DeploymentEventStep) in words, and the log each prints to. Taking the code,
      # building and publishing the image print to the build log, and the rest to the deployment's own log.
      STEPS = {
        "SNAPSHOT_CODE" => "take the code", "BUILD_IMAGE" => "build", "PUBLISH_IMAGE" => "publish the image",
        "WAIT_FOR_DEPENDENCIES" => "wait for dependencies", "MIGRATE_VOLUMES" => "migrate volumes", "PRE_DEPLOY_COMMAND" => "pre-deploy command",
        "CREATE_CONTAINER" => "create containers", "HEALTHCHECK" => "healthcheck", "CONFIGURE_NETWORK" => "configure the network",
        "DRAIN_INSTANCES" => "drain old instances"
      }.freeze
      BUILD_STEPS = %w[SNAPSHOT_CODE BUILD_IMAGE PUBLISH_IMAGE].freeze
      STEP_LIMIT = 50
      # A step's log is read to a little past when it completed.
      STEP_MARGIN = 1.minute

      def deployment_run(deployment, events: nil)
        meta = deployment["meta"].is_a?(Hash) ? deployment["meta"] : {}
        status = status_of(deployment, events: events)
        Capabilities::History::Run.new(
          id: deployment["id"], name: "deploy", status: status, started_at: Telemetry.parse_time(deployment["createdAt"]),
          finished_at: ended_at(deployment, status),
          detail: ("#{meta['commitHash'].to_s.first(12)} #{meta['commitMessage'].to_s.lines.first.to_s.strip}".strip if meta["commitHash"].present?)
        )
      end
      private :deployment_run

      # One deployment of this service in this environment by its id, with each step it went through. Railway documents
      # no address for a deployment's page, so it links to the service.
      def one_deployment(environment_row, resource, asked)
        id = asked.to_s.strip
        deployment = own_deployment!(environment_row, resource, id)

        events = api(environment_row).deployment_events(id, limit: STEP_LIMIT).sort_by { |event| event["createdAt"].to_s }
        run = deployment_run(deployment, events: events)
        run = run.with(parts: events.map { |event| step_part(resource, run, event) })
        Capabilities::History.result([ run ], what: resource[:name], link: link(environment_row, resource))
      end
      private :one_deployment

      def step_part(resource, run, event)
        payload = event["payload"].is_a?(Hash) ? event["payload"] : {}
        started_at = Telemetry.parse_time(event["createdAt"])
        finished_at = Telemetry.parse_time(event["completedAt"])
        status = if payload["error"].present? then Capabilities::History::FAILED
        elsif finished_at || payload["skipped"] then Capabilities::History::SUCCEEDED
        elsif run.finished? then run.status
        else Capabilities::History::RUNNING
        end
        log = { "resource" => resource[:id], "type" => BUILD_STEPS.include?(event["step"]) ? BUILD : APP, "deployment" => run.id, ENVIRONMENT => @asked_environment,
                "start" => run.started_at&.utc&.iso8601, "end" => (finished_at && (finished_at + STEP_MARGIN).utc.iso8601) }.compact
        Capabilities::History::Part.new(
          id: event["id"], name: STEPS.fetch(event["step"].to_s) { event["step"].to_s.downcase.tr("_", " ") }, status: status,
          started_at: started_at, finished_at: finished_at, detail: payload["error"].presence || ("skipped" if payload["skipped"]),
          log: { Capabilities::History::LOG_TOOL => "search_logs", Capabilities::History::LOG_ARGUMENTS => log }
        )
      end
      private :step_part

      def restart_deployment(environment_row:, arguments:)
        resource = find_resource(environment_row, arguments["resource"])
        latest = resource[:instance]["latestDeployment"]
        fail! "#{resource[:name]} has no deployment to restart. Deploy it in Railway first." unless latest

        api(environment_row).restart(latest["id"])
        Telemetry.result("Railway is restarting deployment #{latest['id']} of #{resource[:name]}, without building it again.", link: link(environment_row, resource))
      end

      def rollback_deployment(environment_row:, arguments:)
        resource = find_resource(environment_row, arguments["resource"])
        wanted = arguments["deployment"].to_s.strip
        fail! "Say which deployment to go back to, by the id list_deployments shows." if wanted.empty?

        deployments = api(environment_row).deployments(project_of(environment_row), environment(environment_row)["id"], resource[:id], limit: ROLLBACK_LOOKUP)
        target = deployments.find { |deployment| deployment["id"] == wanted }
        fail! "Deployment #{wanted} is not among the latest #{ROLLBACK_LOOKUP} deployments of #{resource[:name]}. list_deployments shows them." unless target
        unless target["canRollback"]
          fail! "Railway can no longer roll #{resource[:name]} back to deployment #{wanted}, since it no longer keeps its image. Redeploy " \
                "the commit it ran in Railway instead, which builds it again."
        end

        api(environment_row).rollback(wanted)
        Telemetry.result("Railway is rolling #{resource[:name]} back to deployment #{wanted}, with the image and variables it had.", link: link(environment_row, resource))
      end

      # One region's replicas, committed with every region the service runs in, the others as they were, as railway scale
      # merges the regions asked into the ones there and commits them together (railwayapp/cli, src/commands/scale.rs and
      # src/controllers/regions.rs, merge_config and build_multi_region_patch). Only a region the service already runs in is
      # scaled, since placing replicas somewhere new is a choice of where it runs.
      def scale_service(environment_row:, arguments:)
        resource = find_resource(environment_row, arguments["resource"])
        count = Integer(arguments["instances"], exception: false)
        regions = regions_of(resource)
        fail! "Railway has no region for #{resource[:name]} yet, so it cannot be scaled before its first deployment." if regions.empty?

        region = scaled_region(resource, regions, arguments["region"])
        lowest = regions.size > 1 ? 0 : 1
        fail! "instances must be a whole number from #{lowest} to #{MAX_REPLICAS}." unless count && count.between?(lowest, MAX_REPLICAS)

        after = regions.transform_values { |replicas| replicas || 1 }.merge(region => count)
        total = after.values.sum
        fail! "#{resource[:name]} would run #{total} replicas across its regions, and Railway runs at most #{MAX_REPLICAS}." if total > MAX_REPLICAS
        fail! "#{resource[:name]} would run no replicas in any region. Keep at least one, or stop its deployment instead." if total.zero?

        before = regions[region]
        patch = { "services" => { resource[:id] => { "deploy" => { "multiRegionConfig" => after.transform_values { |replicas| { "numReplicas" => replicas } } } } } }
        api(environment_row).patch_commit(environment(environment_row)["id"], patch, "Scale service #{resource[:name]} to #{count} replicas in #{region} from Firefight")
        others = after.except(region).map { |name, replicas| "#{replicas} in #{name}" }
        Telemetry.result("Railway is scaling #{resource[:name]} to #{count} replicas in #{region}#{" from #{before}" if before}" \
                         "#{", keeping #{others.to_sentence}" if others.any?}.", link: link(environment_row, resource))
      end

      # The region a scale names, or the only one the service runs in.
      def scaled_region(resource, regions, asked)
        asked = asked.to_s.strip
        if asked.empty?
          return regions.keys.first if regions.one?

          fail! "#{resource[:name]} runs in #{regions.map { |name, replicas| "#{name} (#{replicas} #{'replica'.pluralize(replicas)})" }.to_sentence}. Name the region to scale, " \
                "and the others keep their replicas."
        end
        regions.keys.find { |name| name.casecmp?(asked) } ||
          fail!("#{resource[:name]} runs in #{regions.keys.to_sentence}, not #{asked}. Railway adds a region in the service's settings.")
      end
      private :scaled_region

      # Kept to the connection's projects, by every project the query's words, its variables and its answer name.
      def api_read(environment_row:, arguments:)
        call = begin
          ReadGuards::Railway.reading(ApiReads::TOOL, arguments)
        rescue ReadGuards::Refused => error
          fail!(error.message)
        end
        text, variables = call.values_at(ReadGuards::Railway::QUERY, ReadGuards::Railway::VARIABLES)
        settings = ConnectionSettings.of(environment_row)
        named = projects_named(text, variables).uniq
        outside = ApiReads.outside_scopes(settings, named, "projects")
        fail_policy!(outside) if outside

        answer = api(environment_row).read(text, variables)
        outside = ApiReads.outside_scopes(settings, projects_in(answer), "projects")
        fail_policy!(outside) if outside

        shown = ApiReads.answer(PROVIDER, "the query #{text.squish.truncate(200)}", answer, secret: ReadGuards::Railway.secret?(text))
        Telemetry.result(shown, link: read_link(environment_row, named))
      end

      PROJECT_ID = /\Aproject_?ids?\z/i
      # A project a query names by projectId or as project(id: ...), written in or passed as a variable.
      LITERAL_PROJECTS = [ /projectIds?\s*:\s*"([^"]+)"/, /\bproject\s*\(\s*id\s*:\s*"([^"]+)"/ ].freeze
      VARIABLE_PROJECTS = [ /projectIds?\s*:\s*\$(\w+)/, /\bproject\s*\(\s*id\s*:\s*\$(\w+)/ ].freeze

      def projects_named(text, variables)
        names = variables.keys.map(&:to_s).select { |name| name.match?(PROJECT_ID) } + VARIABLE_PROJECTS.flat_map { |pattern| text.scan(pattern).flatten }
        from_variables = names.uniq.flat_map { |name| Array(variables[name]) }
        from_variables.map(&:to_s) + LITERAL_PROJECTS.flat_map { |pattern| text.scan(pattern).flatten }
      end
      private :projects_named

      # Every project an answer names, by a projectId, a project's id or a projects list.
      def projects_in(value)
        case value
        when Hash
          own = [ value["projectId"], (value["project"]["id"] if value["project"].is_a?(Hash)) ]
          listed = value["projects"]
          listed = listed["edges"] if listed.is_a?(Hash)
          own += Array(listed).filter_map { |edge| edge.is_a?(Hash) ? (edge["node"] || edge)["id"] : nil }
          own.compact.map(&:to_s) + value.values.flat_map { |inner| projects_in(inner) }
        when Array then value.flat_map { |inner| projects_in(inner) }
        else []
        end
      end
      private :projects_in

      # The page of the one project the query named, as railway open prints it without an environment, or nil.
      def read_link(environment_row, named)
        return nil unless named.one?

        Telemetry::Link.new(provider: PROVIDER, url: "#{site(environment_row)}/project/#{ERB::Util.url_encode(named.first)}")
      end
      private :read_link

      # The environment on the resource map: its services, databases and cron jobs, the repositories they build from and
      # the domains they serve.
      def map_of(environment_row)
        map_of_scopes(environment_row, kinds: MAP_KINDS) { |pack| pack.map_of_project(environment_row) }
      end

      # What a sweep puts on the map for one project.
      MAP_KINDS = (KINDS.values.uniq + [ ResourceMap::KIND_DOMAIN, ResourceMap::KIND_REPOSITORY ]).freeze

      def map_of_project(environment_row)
        project = project_of(environment_row)
        environment = environment(environment_row)
        account = "#{project}/#{environment['id']}"
        found = []
        links = []
        resources(environment_row).each { |resource| read_resource(environment_row, project, environment, account, resource, found, links) }
        gaps = []
        uses, endpoints = settings(environment_row, account, links, gaps)
        listed = instances(environment_row)
        if listed.incomplete?
          gaps << ResourceMap::Gap.new(text: "Only the first #{listed.items.size} services were read.",
                                       kinds: KINDS.values.uniq + [ ResourceMap::KIND_DOMAIN, ResourceMap::KIND_REPOSITORY ])
        end
        ResourceMap::Snapshot.new(resources: found, links: links, gaps: gaps, uses: uses, endpoints: endpoints)
      end

      # Only the service a change named (Integrations::MapEventSources::Railway), read again as the sweep reads it, with
      # where its variables point. A project's webhook sends every environment's changes, so one about another
      # environment reads nothing here. Gone only when Railway answers that the service is not there. nil for a scope
      # Railway cannot narrow to, which a sweep reads.
      def map_refresh(environment_row, scope)
        return unless scope.external_id && (scope.kind.nil? || KINDS.value?(scope.kind))
        if every_scope?(environment_row)
          holder = project_holding(environment_row, scope)
          return holder.map_refresh(environment_row, scope) if holder

          # A change in a project the connection does not read changes nothing here.
          return scope.account ? ResourceMap::Snapshot.new(resources: []) : nil
        end

        project = project_of(environment_row)
        environment = environment(environment_row)
        account = "#{project}/#{environment['id']}"
        return ResourceMap::Snapshot.new(resources: []) if scope.account && scope.account != account

        instance = begin
          api(environment_row).service_instance(environment["id"], scope.external_id)
        rescue RailwayApi::NotFound
          return ResourceMap::Snapshot.new(resources: [], gone: KINDS.values.uniq.map { |kind| [ PROVIDER_KEY, account, kind, scope.external_id ] })
        end
        return unless instance

        resource = resource_of(instance)
        found = []
        links = []
        read_resource(environment_row, project, environment, account, resource, found, links)
        gaps = []
        uses, endpoints = settings(environment_row, account, links, gaps, only: [ resource ])
        ResourceMap::Snapshot.new(resources: found, links: links, gaps: gaps, uses: uses, endpoints: endpoints)
      end

      # One service, database or cron job with the repository it builds from and the domains it serves, onto found and links.
      def read_resource(environment_row, project, environment, account, resource, found, links)
        instance = resource[:instance]
        latest = instance["latestDeployment"] || {}
        item = ResourceMap::Found.new(
          provider: PROVIDER_KEY, account: account, kind: KINDS.fetch(resource[:type]), external_id: resource[:id], name: resource[:name],
          status: latest["status"]&.downcase, url: service_url(environment_row, project, environment["id"], resource[:id]),
          details: { "type" => resource[:engine] ? "#{resource[:engine]} #{DATABASE}" : resource[:type], ResourceMap::INSTANCES => instance["numReplicas"],
                     "region" => instance["region"], ResourceMap::DEPLOYED_COMMIT => latest.dig("meta", "commitHash") }.compact
        )
        found << item
        repository(item, instance.dig("source", "repo"), found, links)
        domains = instance["domains"] || {}
        (Array(domains["serviceDomains"]) + Array(domains["customDomains"])).filter_map { |domain| domain["domain"].presence }.uniq.each do |host|
          domain = ResourceMap.domain(host)
          found << domain
          links << ResourceMap::FoundLink.new(from: domain.key, to: item.key, relation: ResourceMap::RELATION_SERVED_BY)
        end
      end
      private :read_resource

      # How many services' variables one sweep reads. Railway allows a Free plan's token 100 requests an hour (docs,
      # content/docs/reference/public-api.md, Rate Limits), which the hourly sweep shares with everything else the token
      # does, so a project with more services is read a share at a time, a different share each hour.
      SETTINGS_PER_SWEEP = 20
      # A reference to another service's variable, as Railway writes it in a variable's value (docs,
      # content/docs/guides/variables.md, Reference Variables), such as ${{Postgres.DATABASE_URL}}. shared names the
      # project's shared variables, not a service.
      REFERENCE = /\$\{\{\s*([^.{}]+?)\s*\.\s*([A-Za-z0-9_]+)\s*\}\}/
      SHARED = "shared".freeze
      # Variables Railway provides each service with the names it answers on, its private domain and the public TCP
      # proxy in front of a database when it has one (docs, content/docs/reference/variables.md, Railway-provided variables).
      PRIVATE_DOMAIN = "RAILWAY_PRIVATE_DOMAIN".freeze
      PROXY_DOMAIN = "RAILWAY_TCP_PROXY_DOMAIN".freeze
      PROXY_PORT = "RAILWAY_TCP_PROXY_PORT".freeze
      # The port each database engine Railway runs listens on inside the project, as its templates set it.
      ENGINE_PORTS = { "Postgres" => 5432, "Redis" => 6379, "MongoDB" => 27_017, "MySQL" => 3306, "Memcached" => 11_211 }.freeze
      SLOWED = "Railway asked Firefight to slow down, so the rest of the services' variables were not read this time.".freeze

      # Where each service's variables point, read in memory. A reference to a database on the map is a declared link
      # naming the variable, a sealed variable is known by its name only, and a database's own private domain and TCP
      # proxy are where it is reached. Only a share of the services is read each sweep (SETTINGS_PER_SWEEP), and the
      # rest keep what an earlier sweep read. only reads those resources alone, as a re-read does, listing the others
      # only when a variable names one by its name.
      def settings(environment_row, account, links, gaps, only: nil)
        api = api(environment_row)
        share = only || share_of(resources(environment_row).sort_by { |resource| resource[:id] }, gaps)
        by_name = -> { @by_name ||= resources(environment_row).index_by { |resource| resource[:name] } }
        workspace = environment_row.integration.workspace
        share.each_with_object([ [], [] ]) do |resource, (uses, endpoints)|
          unrendered, rendered = api.service_variables(project_of(environment_row), environment(environment_row)["id"], resource[:id])
          key = [ PROVIDER_KEY, account, KINDS.fetch(resource[:type]), resource[:id] ]
          if resource[:type] == DATABASE
            endpoints.concat(database_endpoints(key, resource, rendered, workspace))
            next
          end
          declared(key, account, unrendered, by_name, links)
          sealed = rendered.select { |_, value| value.nil? }.keys
          uses.concat(ResourceMap::Use.read(from: key, workspace: workspace, values: rendered.compact.reject { |name, _| name.start_with?("RAILWAY_") },
                                            names: sealed))
        rescue Integrations::RateLimited
          gaps << ResourceMap::Gap.new(text: SLOWED, kinds: [], settings: true)
          break [ uses, endpoints ]
        rescue RailwayApi::Error => error
          gaps << ResourceMap::Gap.new(text: Sentence.join("The variables of #{resource[:name]} could not be read", error), kinds: [], settings: true)
        end
      end

      # The services this sweep reads variables for, a different share each hour when there are more than a sweep reads.
      def share_of(all, gaps)
        return all if all.size <= SETTINGS_PER_SWEEP

        gaps << ResourceMap::Gap.new(text: "The variables of #{SETTINGS_PER_SWEEP} of #{all.size} services were read this hour, to stay within " \
                                           "Railway's request limit. The others are read in the hours that follow.", kinds: [], settings: true)
        start = (Time.current.to_i / 1.hour.to_i * SETTINGS_PER_SWEEP) % all.size
        all.rotate(start).first(SETTINGS_PER_SWEEP)
      end

      # A variable set to a reference to a database on the map says outright that the service uses it.
      def declared(key, account, unrendered, by_name, links)
        unrendered.each do |name, value|
          value.to_s.scan(REFERENCE).each do |service_name, _|
            target = by_name.call[service_name] unless service_name == SHARED
            next if service_name == SHARED || target.nil? || target[:type] != DATABASE

            to = [ PROVIDER_KEY, account, ResourceMap::KIND_DATABASE, target[:id] ]
            index = links.index { |link| link.from == key && link.to == to && link.relation == ResourceMap::RELATION_USES }
            found = ResourceMap::FoundLink.new(from: key, to: to, relation: ResourceMap::RELATION_USES,
                                               variables: ((index ? links[index].variables : []) + [ name ]).uniq.sort)
            index ? links[index] = found : links << found
          end
        end
      end

      def database_endpoints(key, resource, rendered, workspace)
        private_port = ENGINE_PORTS[resource[:engine]]
        [
          (ResourceMap::Endpoint.at(resource: key, host: rendered[PRIVATE_DOMAIN], port: private_port, workspace: workspace) if private_port),
          ResourceMap::Endpoint.at(resource: key, host: rendered[PROXY_DOMAIN], port: rendered[PROXY_PORT], workspace: workspace)
        ].compact
      end
      private :settings, :share_of, :declared, :database_endpoints

      # What normal looks like for its services and databases: a week of CPU and memory, one reading an hour. A resource
      # Railway cannot read keeps yesterday's baselines, and being asked to slow down stops the whole read.
      def baselines_of(environment_row, resources, window)
        return by_scope(environment_row, resources) { |pack, group| pack.baselines_of(environment_row, group, window) } unless scope

        api = api(environment_row)
        environment_id = environment(environment_row)["id"]
        resources.flat_map do |resource|
          next [] unless KINDS.value?(resource.kind)

          answered = api.metrics("serviceId" => resource.external_id, "environmentId" => environment_id, "startDate" => window.begin.utc.iso8601,
                                 "endDate" => window.end.utc.iso8601, "sampleRateSeconds" => BASELINE_SAMPLE,
                                 "measurements" => BASELINE_METRICS.map { |name| MEASUREMENTS.fetch(name).first })
          BASELINE_METRICS.filter_map do |name|
            measurement, title, unit = MEASUREMENTS.fetch(name)
            points = answered.select { |each| each["measurement"] == measurement }.flat_map { |each| points(each["values"]) }
            ResourceMap::Baseline::Found.new(key: resource.key, metric: name, label: title, unit: unit, points: points) if points.any?
          end
        rescue Integrations::RateLimited
          raise
        rescue RailwayApi::Error => error
          Rails.logger.warn("baseline_sweep.resource_failed resource=#{resource.id} error=#{error.message}")
          []
        end
      end

      # Finds the environment in each project the connection reaches, so one the token can no longer read is said on the
      # connection.
      def check_health!(environment_row)
        ConnectionSettings.of(environment_row).scopes.each { |project| scoped(project).send(:environment, environment_row) }
      rescue RailwayApi::Error => error
        fail! error.message
      end

      private

      def api(environment_row)
        token = ConnectionSettings.of(environment_row).credential(API_TOKEN)
        fail! "This environment has no Railway token. Reconnect it on the Integrations page." if token.blank?

        RailwayApi.new(token)
      end

      def project_of(environment_row) = scope!(environment_row)

      def scope_label(environment_row) = ConnectionSettings.of(environment_row).scope_name(project_of(environment_row))

      # A listing of every project the connection reaches, each read by a pack of its own.
      def every_project(environment_row)
        texts = ConnectionSettings.of(environment_row).scopes.map do |project|
          Array(yield(scoped(project))["content"]).filter_map { |part| part["text"] }.join("\n")
        end
        Telemetry.result(texts.join("\n\n"), link: nil)
      end

      # The pack of the project a change is in, the one its account names or the one the map has the service in, or nil
      # for the sweep to find.
      def project_holding(environment_row, scope)
        reached = ConnectionSettings.of(environment_row).scopes
        named = scope.account.to_s.split("/").first
        return scoped(named) if named.present? && reached.include?(named)
        return if named.present?

        on_map = Scopes.holding(environment_row, scope.external_id)
        scoped(on_map) if on_map.present? && reached.include?(on_map)
      end

      def environment(environment_row)
        @environment ||= if @asked_environment
          other = other_environment(environment_row, @asked_environment)
          @changing ? own_environment_only!(environment_row, other) : other
        else
          connection_environment(environment_row)
        end
      end

      def connection_environment(environment_row)
        asked = ConnectionSettings.of(environment_row).field(ENVIRONMENT) || fail!("This environment has no Railway environment. Reconnect it.")
        self.class.environment_in(api(environment_row).project(project_of(environment_row)), asked)
      end

      # A change acts only in the connection's own environment, since what a person may change is granted per connection
      # and so per environment. Naming another is refused as Firefight's rule, and reads go on reaching every one.
      def own_environment_only!(environment_row, asked)
        own = connection_environment(environment_row)
        return own if asked["id"] == own["id"]

        fail_policy!("A change acts only in this connection's own Railway environment, #{own['name']}, and #{asked['name']} is another. " \
                     "Connect #{asked['name']} as an environment of its own on the Integrations page to change it there.")
      end

      # An environment of the project a call named, its PR environments among them, by name or id.
      def other_environment(environment_row, asked)
        listed = project_environments(environment_row)
        rows = listed.items.map { |each| { id: each["id"], name: each["name"], environment: each } }
        found = Named.find(rows, asked, id: :id, name: :name, provider: PROVIDER)&.dig(:environment)
        return found if found

        fail! "Project #{scope_label(environment_row)} has no environment called #{asked}. It has #{listed.items.map { |each| each['name'] }.join(', ').presence || 'none'}."
      end

      def project_environments(environment_row) = @project_environments ||= api(environment_row).environments(project_of(environment_row))

      # The project's other environments, for a call to name one. A PR environment says which pull request it is for.
      def other_environments(environment_row)
        others = project_environments(environment_row).items.reject { |each| each["id"] == environment(environment_row)["id"] }
        return nil if others.empty?

        rows = others.map do |each|
          pull = each.dig("meta", "prNumber")
          title = each.dig("meta", "prTitle").presence
          about = if pull then "PR environment for pull request ##{pull}#{" #{title}" if title}"
          elsif each["isEphemeral"] then "PR environment"
          end
          "#{each['name']} (#{each['id']})#{", #{about}" if about}"
        end
        "Other environments of the project, each read by passing it as environment:\n#{rows.join("\n")}"
      rescue Integrations::RateLimited
        raise
      rescue RailwayApi::Error => error
        Sentence.join("The project's other environments could not be listed", error)
      end

      def resources(environment_row) = @resources ||= instances(environment_row).items.map { |instance| resource_of(instance) }

      def resource_of(instance)
        engine = engine_of(instance.dig("source", "image"))
        type = if instance["cronSchedule"].present? then CRON_JOB
        elsif engine then DATABASE
        else SERVICE
        end
        { id: instance["serviceId"], name: instance["serviceName"], type: type, engine: engine, instance: instance }
      end

      # The environment's service instances, as a Pages::Read that says whether they were read to the end.
      def instances(environment_row) = @instances ||= api(environment_row).service_instances(project_of(environment_row), environment(environment_row)["id"])

      # A count per step as a count per minute, so a live reading can be compared with a baseline.
      def per_minute(points, step_seconds) = points.map { |at, value| [ at, value * 60.0 / step_seconds ] }

      def engine_of(image) = ENGINES.find { |_, words| words.any? { |word| image.to_s.downcase.include?(word) } }&.first

      def find_resource(environment_row, asked)
        fail! "Say which service, by name or id. list_resources shows them." if asked.to_s.strip.empty?

        found = Named.find(resources(environment_row), asked, id: :id, name: :name, provider: PROVIDER, connection: environment_row)
        return found if found
        fail!("Nothing called #{asked} in this environment. list_resources shows what there is.") if instances(environment_row).complete

        resource_by_id(environment_row, asked.to_s.strip) ||
          fail!("Only the first #{resources(environment_row).size} services were read, and none is called #{asked}. " \
                "Name it by its id, which Railway shows in the service's settings.")
      end

      # A service past the listing's cut, read by its id.
      def resource_by_id(environment_row, id)
        instance = api(environment_row).service_instance(environment(environment_row)["id"], id)
        resource_of(instance) if instance.present?
      rescue RailwayApi::NotFound
        nil
      end

      # The service page, as the CLI prints it (railwayapp/cli, src/commands/up.rs). Railway documents no address for a
      # deployment, logs or metrics page, so every result links to the service.
      def service_url(environment_row, project, environment_id, service_id) = "#{site(environment_row)}/project/#{project}/service/#{service_id}?environmentId=#{environment_id}"

      # Railway's app, the registry's site for this provider.
      def site(environment_row) = ConnectionSettings.of(environment_row).site

      def link(environment_row, resource)
        Telemetry::Link.new(provider: PROVIDER, url: service_url(environment_row, project_of(environment_row), environment(environment_row)["id"], resource[:id]))
      end

      # The project page, as railway open prints it (railwayapp/cli, src/commands/open.rs).
      def project_link(environment_row)
        Telemetry::Link.new(provider: PROVIDER, url: "#{site(environment_row)}/project/#{project_of(environment_row)}?environmentId=#{environment(environment_row)['id']}")
      end

      # Railway's log filter (docs, content/docs/observability/logs.md): quoted phrases, - to leave one out, AND between.
      def filter(*parts, arguments)
        words = parts.compact
        words << quoted(arguments["text"]) if arguments["text"].present?
        words << "-#{quoted(arguments['exclude'])}" if arguments["exclude"].present?
        words.join(" AND ").presence
      end

      def quoted(text) = "\"#{text.to_s.delete('"')}\""

      # Environment logs filtered to the service, read back from the end of the range, as the CLI reads an anchored window
      # (railwayapp/cli, src/controllers/deployment.rs, anchored_log_window).
      def app_logs(environment_row, resource, started, ended, limit, arguments)
        return deployment_app_logs(environment_row, resource, arguments["deployment"], started, ended, limit, arguments) if arguments["deployment"].present?

        found = api(environment_row).environment_logs(
          "environmentId" => environment(environment_row)["id"], "filter" => filter("@service:#{resource[:id]}", arguments),
          "beforeDate" => stamp(started), "anchorDate" => stamp(ended), "afterDate" => stamp(ended), "afterLimit" => 0, "beforeLimit" => limit
        )
        found.filter_map { |line| log_line(line, line.dig("tags", "deploymentInstanceId")) }.select { |line| line.at.between?(started, ended) }
      end

      # What one deployment printed, such as a deployment that failed its healthcheck and was never the latest. Only one of
      # this service in this environment, so a deployment id never reaches past what the connection reads.
      def deployment_app_logs(environment_row, resource, deployment, started, ended, limit, arguments)
        own_deployment!(environment_row, resource, deployment)
        found = api(environment_row).deployment_logs("deploymentId" => deployment, "filter" => filter(arguments), "limit" => limit,
                                                     "startDate" => started.utc.iso8601, "endDate" => ended.utc.iso8601)
        found.filter_map { |line| log_line(line, deployment) }
      end

      def build_logs(environment_row, resource, started, ended, limit, arguments)
        deployment = deployment_of(environment_row, resource, arguments)
        found = api(environment_row).build_logs("deploymentId" => deployment, "filter" => filter(arguments), "limit" => limit,
                                                "startDate" => started.utc.iso8601, "endDate" => ended.utc.iso8601)
        found.filter_map { |line| log_line(line, deployment) }
      end

      def http_logs(environment_row, resource, started, ended, limit, arguments)
        deployment = deployment_of(environment_row, resource, arguments)
        found = api(environment_row).http_logs("deploymentId" => deployment, "filter" => filter(arguments), "beforeLimit" => limit,
                                               "beforeDate" => stamp(started), "anchorDate" => stamp(ended), "afterDate" => stamp(ended), "afterLimit" => 0)
        found.filter_map do |request|
          at = Telemetry.parse_time(request["timestamp"])
          next unless at

          text = [ request["method"], "#{request['host']}#{request['path']}", request["httpStatus"], ("#{request['totalDuration']}ms" if request["totalDuration"]),
                   request["responseDetails"].presence ].compact.join(" ")
          Telemetry::LogLine.new(at: at, source: request["deploymentInstanceId"].to_s, text: text)
        end
      end

      # A deployment named by its id is read only when it is this service's in this environment, so an id never reaches
      # past what the connection reads.
      def deployment_of(environment_row, resource, arguments)
        asked = arguments["deployment"].presence
        return own_deployment!(environment_row, resource, asked)["id"] if asked

        resource[:instance].dig("latestDeployment", "id") || fail!("#{resource[:name]} has no deployment yet, so it has no build or HTTP logs.")
      end

      def own_deployment!(environment_row, resource, id)
        found = begin
          api(environment_row).deployment(id)
        rescue RailwayApi::NotFound
          nil
        end
        return found if found && found["serviceId"] == resource[:id] && found["environmentId"] == environment(environment_row)["id"]

        fail! "#{resource[:name]} has no deployment #{id} in this environment. deploy_history lists its recent deployments."
      end

      def log_line(line, source)
        at = Telemetry.parse_time(line["timestamp"])
        return unless at

        text = line["severity"].present? ? "#{line['severity']}: #{line['message']}" : line["message"]
        Telemetry::LogLine.new(at: at, source: source.to_s, text: text)
      end

      # RFC 3339 with nanoseconds, as the CLI sends an anchored window's dates.
      def stamp(time) = time.utc.iso8601(9)

      def measurement_charts(environment_row, resource, names, started, ended, sample, page)
        return [] if names.empty?

        answered = api(environment_row).metrics("serviceId" => resource[:id], "environmentId" => environment(environment_row)["id"],
                                                "startDate" => started.utc.iso8601, "endDate" => ended.utc.iso8601, "sampleRateSeconds" => sample,
                                                "measurements" => names.map { |name| MEASUREMENTS.fetch(name).first })
        names.map do |name|
          measurement, title, unit = MEASUREMENTS.fetch(name)
          series = answered.select { |each| each["measurement"] == measurement }.map { |each| Telemetry::Series.new(label: resource[:name], points: points(each["values"])) }
          Telemetry::Chart.new(title: "#{title} of #{resource[:name]}", unit: unit, series: series.presence || [ Telemetry::Series.new(label: resource[:name], points: []) ],
                               from: started, to: ended, link: page.url)
        end
      end

      # Requests by status code at each step. The CLI adds a status's samples up as a count (src/controllers/metrics.rs),
      # so a sample is a count over its step, read here per minute.
      def http_charts(environment_row, resource, names, started, ended, sample, page)
        return [] if names.empty?

        groups = api(environment_row).http_by_status("serviceId" => resource[:id], "environmentId" => environment(environment_row)["id"],
                                                     "startDate" => started.utc.iso8601, "endDate" => ended.utc.iso8601, "stepSeconds" => sample)
        names.map do |name|
          title, digit = HTTP_METRICS.fetch(name)
          matching = groups.select { |group| digit.nil? || group["statusCode"].to_s.start_with?(digit) }
          summed = matching.flat_map { |group| points(group["samples"]) }.group_by(&:first).map { |at, pairs| [ at, pairs.sum(&:last) ] }.sort_by(&:first)
          Telemetry::Chart.new(title: "#{title} of #{resource[:name]}", unit: PER_MINUTE,
                               series: [ Telemetry::Series.new(label: resource[:name], points: per_minute(summed, sample)) ],
                               from: started, to: ended, link: page.url)
        end
      end

      # One chart per percentile asked, from one read of the service's request durations.
      def latency_charts(environment_row, resource, names, started, ended, sample, page)
        return [] if names.empty?

        samples = api(environment_row).http_duration("serviceId" => resource[:id], "environmentId" => environment(environment_row)["id"],
                                                     "startDate" => started.utc.iso8601, "endDate" => ended.utc.iso8601, "stepSeconds" => sample)
        names.map do |name|
          field, title = LATENCY_METRICS.fetch(name)
          readings = points(samples.map { |each| { "ts" => each["ts"], "value" => each[field] } })
          Telemetry::Chart.new(title: "#{title} of #{resource[:name]}", unit: MILLISECONDS, series: [ Telemetry::Series.new(label: resource[:name], points: readings) ],
                               from: started, to: ended, link: page.url)
        end
      end

      # ts is an Int the schema gives no unit for, read by its size as seconds or a finer unit.
      def points(values)
        Array(values).filter_map do |point|
          at = Capabilities::Answers.time_of(point["ts"])
          [ at, point["value"].to_f ] if at && !point["value"].nil?
        end.sort_by(&:first)
      end

      # The replicas in each region, from the latest deployment's manifest, as the CLI reads them (src/controllers/regions.rs,
      # region_data_from_deployment_meta). An older deployment has one region and its replica count instead.
      def regions_of(resource)
        deploy = resource[:instance].dig("latestDeployment", "meta", "serviceManifest", "deploy") || {}
        configured = deploy["multiRegionConfig"]
        if configured.is_a?(Hash)
          return configured.select { |_, value| value.is_a?(Hash) }.transform_values { |value| value["numReplicas"] }
        end
        return { deploy["region"] => deploy["numReplicas"] || 1 } if deploy["region"].present?

        region = resource[:instance]["region"]
        region.present? ? { region => resource[:instance]["numReplicas"] } : {}
      end

      def repository(item, repo, found, links)
        path = repo.to_s.delete_suffix(".git")
        repository = ResourceMap.repository(REPOSITORY_HOST, path) if path.match?(%r{\A[\w.-]+/[\w.-]+\z})
        return unless repository

        found << repository
        links << ResourceMap::FoundLink.new(from: item.key, to: repository.key, relation: ResourceMap::RELATION_BUILT_FROM)
      end

      def status_lines(resource)
        instance = resource[:instance]
        latest = instance["latestDeployment"]
        domains = instance["domains"] || {}
        hosts = (Array(domains["serviceDomains"]) + Array(domains["customDomains"])).map { |domain| "#{domain['domain']}#{" to port #{domain['targetPort']}" if domain['targetPort']}" }
        replicas = Array(latest&.dig("instances")).map { |replica| replica["status"].to_s.downcase }.tally.map { |state, count| "#{count} #{state}" }
        [
          "#{resource[:name]}, #{resource[:engine] ? "#{resource[:engine]} #{DATABASE}" : resource[:type]}",
          (latest ? "Latest deployment: #{deployment_line(latest)}" : "Never deployed"),
          ("Replicas now: #{replicas.join(', ')}" if replicas.any?),
          ("Deployment stopped by hand" if latest&.dig("deploymentStopped")),
          replicas_line(resource),
          source_line(instance),
          ("Health check: #{instance['healthcheckPath']}, timeout #{instance['healthcheckTimeout'] || 300} seconds, checked only while deploying" if instance["healthcheckPath"].present?),
          ("Health check: none, so a deployment counts as up once its container starts" if instance["healthcheckPath"].blank? && resource[:type] == SERVICE),
          "Restart policy: #{instance['restartPolicyType']}#{", at most #{instance['restartPolicyMaxRetries']} times" if instance['restartPolicyType'] == 'ON_FAILURE'}",
          ("Sleeps when idle, so a first request after a quiet spell waits for it to wake" if instance["sleepApplication"]),
          ("Schedule: #{instance['cronSchedule']}, next run #{instance['nextCronRunAt']}" if instance["cronSchedule"].present?),
          ("Domains: #{hosts.join(', ')}" if hosts.any?)
        ]
      end

      # A service in several regions names the replicas in each, as scale_service takes them.
      def replicas_line(resource)
        regions = regions_of(resource)
        return "Replicas by region: #{regions.map { |name, replicas| "#{replicas || 1} in #{name}" }.join(', ')}" if regions.size > 1

        "Replicas: #{resource[:instance]['numReplicas'] || 1}, region #{resource[:instance]['region'] || 'unknown'}"
      end

      def source_line(instance)
        source = instance["source"] || {}
        what = source["repo"].present? ? "Runs #{source['repo']}" : ("Runs the image #{source['image']}" if source["image"].present?)
        [ what, ("start command #{instance['startCommand']}" if instance["startCommand"].present?) ].compact.join(", ").presence
      end

      # meta is untyped JSON. commitHash is the one key the CLI reads (src/commands/mcp/handler.rs), so the rest is read
      # only when it is there.
      def deployment_line(deployment)
        meta = deployment["meta"].is_a?(Hash) ? deployment["meta"] : {}
        commit = ("#{meta['commitHash'].to_s.first(12)}#{" \"#{meta['commitMessage'].to_s.lines.first.to_s.strip}\"" if meta['commitMessage'].present?}" if meta["commitHash"].present?)
        [ deployment["createdAt"], "deployment #{deployment['id']}", deployment["status"], commit,
          ("by #{deployment.dig('creator', 'name').presence || deployment.dig('creator', 'email')}" if deployment["creator"]),
          ("can be rolled back to" if deployment["canRollback"]) ].compact.join(", ")
      end
    end
  end
end
