module Integrations
  module Packs
    # Vercel for the teams an environment reads, one, several or every one its token can reach, or the token's own account
    # when the team connect field (a scope) is left empty. A call reaches one team, the one it names or the one its
    # project lives in (Integrations::Scopes), and a listing named none lists every team. It reads their projects, the
    # projects' deployments, their build and runtime logs, rolling releases and the team's Vercel CI runs, with an access
    # token a person creates in Vercel. Every tool reads, except the rollback, promotion, cancel, redeploy and rolling
    # release steps Halon uses to apply fixes. Paths, parameters and answers are the ones in Vercel's OpenAPI spec
    # (openapi.vercel.sh), and how a rollback, promotion or redeploy is asked follows Vercel's own CLI (vercel/vercel,
    # packages/cli/src/commands).
    # Vercel's remote MCP server only accepts the AI clients Vercel has approved, so Firefight reaches its API directly.
    class Vercel < NativePack
      # The environment row's credentials, which only this pack reads.
      API_TOKEN = "api_token".freeze
      TEAM = "team".freeze

      PROVIDER = "Vercel".freeze
      PROVIDER_KEY = "vercel".freeze
      PRODUCTION = "production".freeze
      READY = "READY".freeze

      LOG_TYPES = %w[runtime build].freeze
      RUNTIME = LOG_TYPES.first
      BUILD = LOG_TYPES.last
      # How long a runtime log read watches the live stream. Vercel's CLI watches for up to 5 minutes, and a tool call
      # stays far shorter.
      DEFAULT_SECONDS = 20
      MAX_SECONDS = 60
      LOG_LIMIT = 200
      DEPLOYMENT_LIMIT = 20
      LATEST_SHOWN = 5
      # How long Vercel keeps runtime logs on each plan (docs, logs/runtime, Limits).
      RETENTION = "1 hour on Hobby, 1 day on Pro, 3 days on Enterprise and 30 days with Observability Plus".freeze
      # Build events that carry a line of output (spec, getDeploymentEvents type).
      OUTPUT_EVENTS = %w[command stdout stderr fatal exit].freeze
      # Commit details Vercel keeps in a deployment's meta, by Git provider (vercel/vercel, commands/bisect/index.ts).
      COMMIT_SHA = %w[githubCommitSha gitlabCommitSha bitbucketCommitSha].freeze
      COMMIT_MESSAGE = %w[githubCommitMessage gitlabCommitMessage bitbucketCommitMessage].freeze
      COMMIT_REF = %w[githubCommitRef gitlabCommitRef bitbucketCommitRef].freeze

      CI_LIMIT = 20
      CI_LIMIT_MAX = 100

      # The metrics query_metrics reads, each a Vercel Observability metric with an aggregation and, for errors, a filter on
      # its HTTP status, by Vercel's own names (vercel.com/docs/cli/metrics, Available metrics and Filter). Requests are
      # what Vercel's CDN served, the rest what the project's functions did.
      Metric = Data.define(:title, :unit, :metric, :aggregation, :filter)
      REQUEST = "vercel.request.count".freeze
      INVOCATION = "vercel.function_invocation".freeze
      METRICS = {
        "requests" => Metric.new(title: "Requests", unit: "requests", metric: REQUEST, aggregation: "sum", filter: nil),
        "http_4xx" => Metric.new(title: "4xx responses", unit: "requests", metric: REQUEST, aggregation: "sum", filter: "httpStatus ge 400 and httpStatus lt 500"),
        "http_5xx" => Metric.new(title: "5xx responses", unit: "requests", metric: REQUEST, aggregation: "sum", filter: "httpStatus ge 500"),
        "invocations" => Metric.new(title: "Function invocations", unit: "invocations", metric: "#{INVOCATION}.count", aggregation: "sum", filter: nil),
        "duration" => Metric.new(title: "Function duration", unit: "ms", metric: "#{INVOCATION}.function_duration_ms", aggregation: "avg", filter: nil),
        "latency_p95" => Metric.new(title: "Function time to first byte, 95th percentile", unit: "ms", metric: "#{INVOCATION}.ttfb_ms", aggregation: "p95", filter: nil),
        "cpu_time" => Metric.new(title: "Function active CPU time", unit: "ms", metric: "#{INVOCATION}.function_cpu_time_ms", aggregation: "sum", filter: nil),
        "memory" => Metric.new(title: "Function peak memory", unit: "MB", metric: "#{INVOCATION}.peak_memory_mb", aggregation: "max", filter: nil)
      }.freeze
      DEFAULT_METRICS = %w[requests http_5xx invocations duration].freeze
      PRODUCTION_FILTER = "environment eq 'production'".freeze
      # The bucket Vercel's CLI picks for a range, the finest it allows (packages/cli/src/commands/metrics/time-utils.ts).
      GRANULARITIES = [ [ 1.hour, { "minutes" => 1 } ], [ 2.hours, { "minutes" => 5 } ], [ 12.hours, { "minutes" => 15 } ],
                        [ 3.days, { "hours" => 1 } ], [ 30.days, { "hours" => 4 } ] ].freeze
      COARSEST = { "days" => 1 }.freeze
      OBSERVABILITY_PLUS = "Vercel answers these metrics only for a Pro or Enterprise team with Observability Plus".freeze

      RESOURCE = { "type" => "string", "description" => "A project in the team, by name or id, as list_resources shows it" }.freeze
      DEPLOYMENT = { "type" => "string", "description" => "A deployment of the project, by its id (dpl_...) or its URL, as list_deployments shows it" }.freeze

      COST_DAYS = 30
      COST_DAYS_MAX = 365
      COST_MONTHS = 3
      COST_MONTHS_MAX = 12
      # A year by day is a few thousand rows for most teams, and a larger one is cut rather than read for minutes.
      COST_ROWS = 50_000

      tool :list_resources,
           summary: "Lists the team's Vercel projects with their production deployment state.",
           description: "The projects in the Vercel team for this environment, with their framework and the state of their " \
                        "production deployment. Use it first to find the name to pass to the other tools",
           params_schema: { "type" => "object", "properties" => {} },
           read_only: true

      tool :describe_resource,
           summary: "Shows a project's setup, domains, production deployment and recent rollbacks.",
           description: "How one project is set up and how it stands now: its framework, Git repository and production branch, " \
                        "the production deployment and its state, its domains, its latest deployments, and how the last " \
                        "rollback or promotion went",
           params_schema: { "type" => "object", "properties" => { "resource" => RESOURCE }, "required" => [ "resource" ] },
           read_only: true

      tool :list_deployments,
           summary: "Lists a project's deployments with their commit, author, state and failures.",
           description: "A project's deployments, newest first: when, production or preview, its state and why it failed, the " \
                        "commit and branch, who made it, its page, and which one serves production now. Use it to see what " \
                        "changed before something broke, and for the id rollback_deployment and promote_deployment take",
           params_schema: {
             "type" => "object",
             "properties" => {
               "resource" => RESOURCE,
               "production_only" => { "type" => "boolean", "description" => "Only production deployments (optional)" },
               "limit" => { "type" => "integer", "description" => "At most this many deployments (optional, #{DEPLOYMENT_LIMIT})" }
             },
             "required" => [ "resource" ]
           },
           read_only: true

      tool :deploy_history,
           summary: "Shows how long a project's recent builds took to go live.",
           description: "A project's recent deployments, each a build and its release, with production or preview, its state, " \
                        "when it started building and when it was ready and how long that took, and how long finished ones usually take",
           params_schema: {
             "type" => "object",
             "properties" => {
               "resource" => RESOURCE,
               "name" => { "type" => "string", "description" => "Only runs of this kind, production or preview (optional)" },
               "run" => { "type" => "string", "description" => "Only this deployment, by its id (dpl_...), with its build and checks and where it failed (optional)" },
               "limit" => { "type" => "integer", "description" => "At most this many deployments (optional, #{DEPLOYMENT_LIMIT})" }
             },
             "required" => [ "resource" ]
           },
           read_only: true

      tool :deployment_logs,
           summary: "Shows a deployment's build output or streams its live function logs.",
           description: "Log lines of one deployment of a project. type build reads its build output, newest first, of the " \
                        "newest deployment unless one is named. type runtime watches what its functions log live, for up to #{MAX_SECONDS} " \
                        "seconds, of the production deployment unless one is named, since Vercel's API gives no past runtime " \
                        "logs. Earlier runtime logs are on the project's Logs page",
           params_schema: {
             "type" => "object",
             "properties" => {
               "resource" => RESOURCE,
               "deployment" => DEPLOYMENT.merge("description" => "#{DEPLOYMENT['description']} (optional)"),
               "type" => { "type" => "string", "enum" => LOG_TYPES, "description" => "Which logs (optional, runtime)" },
               "text" => { "type" => "string", "description" => "Only lines containing this text (optional)" },
               "exclude" => { "type" => "string", "description" => "Leave out lines containing this text (optional)" },
               "seconds" => { "type" => "integer", "description" => "How long to watch runtime logs, in seconds (optional, #{DEFAULT_SECONDS}, at most #{MAX_SECONDS})" },
               "limit" => { "type" => "integer", "description" => "At most this many lines (optional, #{LOG_LIMIT})" }
             },
             "required" => [ "resource" ]
           },
           read_only: true

      tool :rollback_deployment,
           summary: "Rolls a project's production domains back to an earlier deployment.",
           description: "Point a project's production domains back at an earlier production deployment, without building it " \
                        "again. Afterwards new deployments no longer go live on their own until one is promoted with " \
                        "promote_deployment. The Hobby plan can only go back to the previous production deployment",
           params_schema: {
             "type" => "object",
             "properties" => {
               "resource" => RESOURCE, "deployment" => DEPLOYMENT,
               "reason" => { "type" => "string", "description" => "Why, shown with the rollback in Vercel (optional)" }
             },
             "required" => %w[resource deployment]
           },
           read_only: false

      tool :promote_deployment,
           summary: "Promotes a deployment to serve production, undoing a rollback.",
           description: "Make a production deployment of a project serve its production domains, without building it again. " \
                        "It undoes a rollback, and lets new deployments go live on their own again",
           params_schema: {
             "type" => "object",
             "properties" => { "resource" => RESOURCE, "deployment" => DEPLOYMENT },
             "required" => %w[resource deployment]
           },
           read_only: false

      tool :cancel_deployment,
           summary: "Stops a project's deployment that is still building.",
           description: "Stop a deployment of a project while it is queued or building, such as one from the wrong branch or one " \
                        "known to be broken, so it never goes live. A deployment that is ready, failed or canceled cannot be " \
                        "canceled, and a canceled one cannot be started again, so redeploy_deployment builds it anew",
           params_schema: { "type" => "object", "properties" => { "resource" => RESOURCE, "deployment" => DEPLOYMENT }, "required" => %w[resource deployment] },
           read_only: false

      tool :redeploy_deployment,
           summary: "Builds an earlier deployment of a project again, with the same settings.",
           description: "Build a deployment of a project again as a new deployment, with its settings and environment variables " \
                        "as they are now, for the same target: production for a production one, or a preview. Use it for a build " \
                        "that failed for a passing reason, or after a setting was fixed. latest_commit builds the branch's newest " \
                        "commit instead of the deployment's own. A production one goes live when ready, unless the project was " \
                        "rolled back or runs rolling releases",
           params_schema: {
             "type" => "object",
             "properties" => {
               "resource" => RESOURCE, "deployment" => DEPLOYMENT,
               "latest_commit" => { "type" => "boolean", "description" => "Build the branch's newest commit rather than the deployment's (optional, false)" }
             },
             "required" => %w[resource deployment]
           },
           read_only: false

      tool :query_metrics,
           summary: "Charts a project's requests, errors and function time from Vercel Observability.",
           description: "Metrics of one project over time from Vercel Observability: requests its CDN served and how many were " \
                        "4xx and 5xx, its function invocations, their average duration, the time to first byte 95% of " \
                        "invocations stayed within, their active CPU time and peak memory. Production only unless asked " \
                        "otherwise. Returns min, average, max and latest for each, and the person sees each metric as a chart. " \
                        "Vercel answers only for a team with Observability Plus",
           params_schema: {
             "type" => "object",
             "properties" => {
               "resource" => RESOURCE,
               "metrics" => { "type" => "array", "items" => { "type" => "string", "enum" => METRICS.keys },
                              "description" => "Which metrics (optional, #{DEFAULT_METRICS.join(', ')})" },
               "all_environments" => { "type" => "boolean", "description" => "Previews too, not only production (optional, false)" },
               **Capabilities::RANGE
             },
             "required" => [ "resource" ]
           },
           read_only: true

      tool :rolling_release,
           summary: "Shows a project's rolling release, its stages and the traffic the new deployment gets.",
           description: "A project's rolling release: whether it is active, aborted or complete, the deployment being rolled out " \
                        "and the one it replaces, the stage it is at with the share of production traffic the new one gets, " \
                        "whether the next stage waits for approval or moves on its own, and the stages after it",
           params_schema: { "type" => "object", "properties" => { "resource" => RESOURCE }, "required" => [ "resource" ] },
           read_only: true

      tool :advance_rolling_release,
           summary: "Moves a project's rolling release on to its next stage.",
           description: "Move a project's active rolling release on to its next stage, giving the new deployment the larger " \
                        "share of production traffic that stage names. When the next stage is the last, the new deployment " \
                        "serves all production traffic and the rolling release ends. abort_rolling_release goes back",
           params_schema: { "type" => "object", "properties" => { "resource" => RESOURCE }, "required" => [ "resource" ] },
           read_only: false

      tool :complete_rolling_release,
           summary: "Sends all of a project's production traffic to the deployment being rolled out.",
           description: "End a project's active rolling release by sending all production traffic to the deployment being " \
                        "rolled out, skipping the stages left. rollback_deployment to the one it replaced goes back",
           params_schema: { "type" => "object", "properties" => { "resource" => RESOURCE }, "required" => [ "resource" ] },
           read_only: false

      tool :abort_rolling_release,
           summary: "Stops a project's rolling release, sending all traffic back to the deployment it replaced.",
           description: "Stop a project's active rolling release and send all production traffic back to the deployment it was " \
                        "replacing, through an instant rollback to it, as Vercel documents for stopping one. Afterwards new " \
                        "deployments no longer go live on their own until one is promoted with promote_deployment",
           params_schema: { "type" => "object", "properties" => { "resource" => RESOURCE }, "required" => [ "resource" ] },
           read_only: false

      tool :ci_runs,
           summary: "Lists the team's Vercel CI runs, or one run with its jobs.",
           description: "The team's Vercel CI runs, newest first, each with its repository, branch and commit, its status, when it " \
                        "started and finished and how long it took, and how long finished ones usually take. run reads one by " \
                        "its id with each job as a part, its outcome and why it failed, and ci_job_log reads a job's log",
           params_schema: {
             "type" => "object",
             "properties" => {
               "repository" => { "type" => "string", "description" => "Only runs of this repository, as owner/name (optional)" },
               "branch" => { "type" => "string", "description" => "Only runs of this branch (optional)" },
               "name" => { "type" => "string", "description" => "Only runs whose repository contains this (optional)" },
               "run" => { "type" => "string", "description" => "Only this run, by its id, with its jobs (optional)" },
               "limit" => { "type" => "integer", "description" => "At most this many runs (optional, #{CI_LIMIT}, at most #{CI_LIMIT_MAX})" }
             }
           },
           read_only: true

      tool :ci_job_log,
           summary: "Shows the log of one job of a Vercel CI run.",
           description: "The log lines of one job of a Vercel CI run, newest last, as ci_runs names the run and the job",
           params_schema: {
             "type" => "object",
             "properties" => {
               "run" => { "type" => "string", "description" => "The run's id, as ci_runs shows it" },
               "job" => { "type" => "string", "description" => "The job, by its id or name as ci_runs shows it" },
               "text" => { "type" => "string", "description" => "Only lines containing this text (optional)" },
               "limit" => { "type" => "integer", "description" => "At most this many lines, the last ones (optional, #{LOG_LIMIT})" }
             },
             "required" => %w[run job]
           },
           read_only: true

      tool :api_read,
           summary: "Reads any other Vercel detail, such as project settings, domains or firewall rules.",
           description: "Anything else Vercel's API reads that the other tools do not cover, such as a project's settings, " \
                        "domains and their configuration, aliases, a deployment by its id and its files, checks, firewall " \
                        "settings, Edge Config or the team's members. A GET to a path of Vercel's REST API " \
                        "(#{VercelApi::API_ROOT}), written with its version as the API reference the vercel_api skill names " \
                        "writes it, such as /v9/projects/<project>/domains. Always in this connection's team. A list answers one " \
                        "page: pass limit, and the pagination's next as until for the next page. Only reads, so it never " \
                        "changes anything. Environment variables, drains and tokens come back as their names",
           params_schema: ApiReads.path_schema("/v9/projects/<project id or name>/domains"),
           read_only: true

      tool :billing_charges,
           summary: "Shows what the Vercel team was charged and which projects drove the cost.",
           description: "What the Vercel team was charged, by day or by month, with each period's total, the services that cost most and " \
                        "the projects behind them. Use it to watch spend and find what grew and since when. The token's role on the team " \
                        "has to see billing",
           params_schema: {
             "type" => "object",
             "properties" => {
               "by" => { "type" => "string", "enum" => Spend::GRANULARITIES, "description" => "day or month (optional, day)" },
               "days" => { "type" => "integer", "description" => "For by day, how many days back from today (optional, #{COST_DAYS}, at most #{COST_DAYS_MAX})" },
               "months" => { "type" => "integer", "description" => "For by month, how many months before this one (optional, #{COST_MONTHS}, at most #{COST_MONTHS_MAX})" }
             }
           },
           read_only: true

      def self.credential_fields
        [
          CredentialField.new(key: API_TOKEN, label: "Access token", secret: true, placeholder: "",
                              hint: "A Vercel access token created under Account Settings, Tokens, scoped to the team. It acts with the access of the person who created it. " \
                                    "Make it as a dedicated user, such as Firefight, so changes do not show as a teammate and the connection keeps working when someone leaves.")
        ]
      end

      # Lists one project with the token in each team chosen, or in its own account when none is, or lists the teams for
      # every one it can read, so a wrong token or team is said on the form before anything is saved.
      def self.credential_refusal(values, region: nil, fields: {})
        token = values[API_TOKEN].to_s.strip
        teams = Array(fields[TEAM]).map { |each| each.to_s.strip }.compact_blank
        return "Paste an access token." if token.empty?
        return (VercelApi.new(token).teams.items.empty? ? "This token can reach no Vercel teams." : nil) if teams == [ IntegrationProvider::ConnectField::ALL ]

        (teams.presence || [ nil ]).each do |team|
          VercelApi.new(token, team).check!
        rescue VercelApi::Error => error
          return Sentence.join("Vercel refused this token or team#{" #{team}" if team}", error)
        end
        nil
      rescue VercelApi::Error => error
        Sentence.join("Vercel refused this token", error)
      end

      # The teams the token can reach (VercelApi#teams), each by its id and name.
      def self.scope_options(values, region: nil, fields: {})
        token = values.to_h.stringify_keys[API_TOKEN].to_s.strip
        raise NativePack::Error, "Paste an access token first." if token.empty?

        VercelApi.new(token).teams.items.map do |team|
          IntegrationProvider::ConnectOption.new(value: team["id"].to_s, label: team["name"].presence || team["slug"].presence || team["id"].to_s)
        end
      rescue VercelApi::Error => error
        raise NativePack::Error, Sentence.join("Vercel did not list this token's teams", error)
      end

      def self.store_credentials!(environment_row, values)
        environment_row.store_credential!(API_TOKEN, values[API_TOKEN].to_s.strip)
      end

      def list_resources(environment_row:, arguments:)
        return every_team(environment_row) { |pack| pack.list_resources(environment_row: environment_row, arguments: arguments) } if every_scope?(environment_row)

        rows = projects(environment_row).map do |project|
          production = project.dig("targets", PRODUCTION)
          state = production ? "production #{production['readyState'].to_s.downcase}" : "no production deployment"
          [ "#{project['name']} (#{project['id']})", project["framework"], state, ("paused" if project["paused"]) ].compact.join(", ")
        end
        team = team_of(environment_row)
        named = team ? "Team #{ConnectionSettings.of(environment_row).scope_name(team)}" : "This team"
        cut = project_list(environment_row).incomplete? ? " Only the first #{rows.size} projects were read." : ""
        text = rows.empty? ? "#{named} has no projects." : "#{named}, #{rows.size} projects.#{cut}\n#{rows.join("\n")}"
        Telemetry.result(text, link: team_link(environment_row))
      end

      def describe_resource(environment_row:, arguments:)
        project = find_project(environment_row, arguments["resource"])
        detail = api(environment_row).project(project["id"])
        production = detail.dig("targets", PRODUCTION)
        domains = api(environment_row).project_domains(project["id"]).items
        latest = Array(detail["latestDeployments"]).first(LATEST_SHOWN)
        lines = [
          "#{detail['name']}, #{detail['framework'] || 'no framework set'}#{', paused' if detail['paused']}",
          repository_line(detail["link"]),
          (production ? "Production: #{deployment_line(production)}" : "Production: no deployment yet"),
          alias_request_line(detail["lastAliasRequest"]),
          ("Domains:\n#{domains.map { |domain| domain_words(domain) }.join("\n")}" if domains.any?),
          ("Latest deployments:\n#{latest.map { |deployment| deployment_line(deployment) }.join("\n")}" if latest.any?)
        ]
        Telemetry.result(lines.compact.join("\n"), link: project_link(environment_row, detail))
      end

      def list_deployments(environment_row:, arguments:)
        project = find_project(environment_row, arguments["resource"])
        target = PRODUCTION if ActiveModel::Type::Boolean.new.cast(arguments["production_only"])
        deployments = api(environment_row).deployments(project["id"], limit: Capabilities::Answers.limit(arguments, DEPLOYMENT_LIMIT), target: target)
        link = project_link(environment_row, project)
        return Telemetry.result("#{project['name']} has no deployments.", link: link) if deployments.empty?

        current = project.dig("targets", PRODUCTION, "id")
        rows = deployments.map { |deployment| deployment_line(deployment, current: current) }
        result = Telemetry.result("Latest #{rows.size} deployments of #{project['name']}, newest first. rollback_deployment and promote_deployment take an id.\n" \
                                  "#{rows.join("\n")}", link: link)
        Capabilities::Deploys.with_deploys(result, deployments.map { |deployment| deploy_of(deployment, current) })
      end

      # The one serving production is the project's production target. Every other deployment does not serve it, and
      # without a target Vercel does not say which serves. A deployment with no target is a preview.
      def deploy_of(deployment, current)
        id = deployment["uid"] || deployment["id"]
        Capabilities::Deploys::Deploy.new(
          id: id, commit: meta(deployment, COMMIT_SHA), branch: meta(deployment, COMMIT_REF),
          status: Capabilities::Deploys.status(deployment["readyState"] || deployment["state"], DEPLOYMENT_STATES),
          live: (id == current if current), started_at: millis(deployment["buildingAt"] || deployment["createdAt"] || deployment["created"]),
          finished_at: millis(deployment["ready"]), environment: deployment["target"].presence || PREVIEW_TARGET
        )
      end
      private :deploy_of

      PREVIEW_TARGET = "preview".freeze

      # Vercel's deployment states (spec, getDeployments, readyState) in Firefight's words.
      DEPLOYMENT_STATES = {
        "initializing" => Capabilities::History::QUEUED, "queued" => Capabilities::History::QUEUED,
        "building" => Capabilities::History::RUNNING, "ready" => Capabilities::History::SUCCEEDED,
        "error" => Capabilities::History::FAILED, "canceled" => Capabilities::History::CANCELLED
      }.freeze

      # A deployment from when it started building (buildingAt, or createdAt before it did) to when it was ready (ready),
      # each in milliseconds (spec, getDeployments). The list gives a failed or canceled one no end, so the newest few of
      # those are read one by one for when their build failed (buildErrorAt) or was canceled (canceledAt). A name of
      # production or preview is asked of Vercel as the target, so the other kind cannot crowd the list.
      def deploy_history(environment_row:, arguments:)
        project = find_project(environment_row, arguments["resource"])
        return one_deployment(environment_row, project, arguments["run"]) if arguments["run"].present?

        deployments = api(environment_row).deployments(project["id"], limit: Capabilities::Answers.limit(arguments, DEPLOYMENT_LIMIT), target: target_named(arguments["name"]))
        runs = with_ends(environment_row, deployments).map { |deployment| history_run(deployment) }
        Capabilities::History.result(runs, what: project["name"], link: project_link(environment_row, project), name: arguments["name"])
      end

      # How many failed or canceled deployments of one list are read again for their end.
      ENDS_READ = 5
      ENDED = %w[READY ERROR CANCELED].freeze
      ENDED_WITHOUT_READY = %w[ERROR CANCELED].freeze

      def target_named(name)
        asked = name.to_s.downcase
        [ PRODUCTION, PREVIEW_TARGET ].find { |target| asked.include?(target) }
      end
      private :target_named

      # The list's deployments, the newest few that failed or were canceled read whole. One Vercel will not read keeps no end.
      def with_ends(environment_row, deployments)
        ended = deployments.select { |deployment| ENDED_WITHOUT_READY.include?((deployment["readyState"] || deployment["state"]).to_s.upcase) }.first(ENDS_READ)
        read = ended.to_h do |deployment|
          id = deployment["uid"] || deployment["id"]
          [ id, api(environment_row).deployment(id) ]
        rescue Integrations::RateLimited
          raise
        rescue VercelApi::Error
          [ id, deployment ]
        end
        deployments.map { |deployment| read[deployment["uid"] || deployment["id"]]&.merge(deployment) { |_key, whole, listed| whole.nil? ? listed : whole } || deployment }
      end
      private :with_ends

      def deployment_logs(environment_row:, arguments:)
        project = find_project(environment_row, arguments["resource"])
        build = arguments["type"].to_s == BUILD
        # A build that failed is the newest deployment, not the one serving production.
        asked = arguments["deployment"].presence || (latest_id(environment_row, project) if build)
        deployment = find_deployment(environment_row, project, asked)
        limit = Capabilities::Answers.limit(arguments, LOG_LIMIT)
        if build
          build_logs(environment_row, project, deployment, arguments, limit)
        else
          runtime_logs(environment_row, project, deployment, arguments, limit)
        end
      end

      def rollback_deployment(environment_row:, arguments:)
        project = find_project(environment_row, arguments["resource"])
        deployment = find_deployment(environment_row, project, arguments["deployment"], required: true)
        begin
          api(environment_row).rollback(project["id"], deployment["id"], description: arguments["reason"].to_s.strip.first(250))
        rescue VercelApi::PlanLimited => error
          fail! Sentence.all(error, "On Vercel's Hobby plan a rollback can only go to the previous production deployment, so pick " \
                                   "that one from list_deployments, or roll back further on a Pro plan.")
        end
        Telemetry.result("Vercel is pointing the production domains of #{project['name']} at #{deployment['id']}. New deployments no " \
                         "longer go live on their own until one is promoted, so promote the fixed deployment with " \
                         "promote_deployment when it is ready. describe_resource shows how the rollback went.",
                         link: project_link(environment_row, project))
      end

      def promote_deployment(environment_row:, arguments:)
        project = find_project(environment_row, arguments["resource"])
        deployment = find_deployment(environment_row, project, arguments["deployment"], required: true)
        unless deployment["target"] == PRODUCTION
          fail! "#{deployment['id']} is a preview deployment. Vercel promotes a preview by building it again for production, " \
                "which this tool does not do. Redeploy it to production in Vercel, then promote that deployment."
        end

        answer = api(environment_row).promote(project["id"], deployment["id"])
        done = if answer.status == 202
          "Vercel queued the promotion of #{deployment['id']} for #{project['name']}. It starts when the rolling release in progress completes."
        else
          "Vercel is pointing the production domains of #{project['name']} at #{deployment['id']}, and new production deployments go live on their own again."
        end
        Telemetry.result("#{done} describe_resource shows how the promotion went.", link: project_link(environment_row, project))
      end

      # Only a deployment of the project that has not ended, since Vercel cancels one only while it builds (spec,
      # cancelDeployment).
      def cancel_deployment(environment_row:, arguments:)
        project = find_project(environment_row, arguments["resource"])
        deployment = find_deployment(environment_row, project, arguments["deployment"], required: true)
        state = (deployment["readyState"] || deployment["state"]).to_s.upcase
        if ENDED.include?(state)
          fail! "#{deployment['id']} of #{project['name']} is #{state.downcase} already, so there is nothing to cancel. redeploy_deployment builds it again."
        end

        canceled = api(environment_row).cancel_deployment(deployment["id"])
        Telemetry.result("Vercel stopped the build of #{deployment['id']} for #{project['name']}, which is now " \
                         "#{(canceled['readyState'] || 'canceled').to_s.downcase} and never goes live. redeploy_deployment builds it again.",
                         link: inspector_link(canceled) || inspector_link(deployment) || project_link(environment_row, project))
      end

      # Whoever made the deployment a cancel would stop, as Vercel names them. Vercel gives a username and no address, and
      # a deployment made by an app, integration or Vercel itself has nobody to ask.
      def owner_of(tool_name, environment_row:, arguments:)
        return super unless tool_name == "cancel_deployment"

        project = find_project(environment_row, arguments["resource"])
        deployment = find_deployment(environment_row, project, arguments["deployment"], required: true)
        creator = deployment["creator"].to_h
        return if creator["username"].blank? || [ nil, "user" ].exclude?(creator["type"])

        Owner.new(name: creator["username"], role: Owner::ROLE_STARTED, what: "deployment #{deployment['id']} of #{project['name']}")
      end

      def redeploy_deployment(environment_row:, arguments:)
        project = find_project(environment_row, arguments["resource"])
        deployment = find_deployment(environment_row, project, arguments["deployment"], required: true)
        latest = ActiveModel::Type::Boolean.new.cast(arguments["latest_commit"]) == true
        made = api(environment_row).redeploy(deployment, latest_commit: latest)
        id = made["id"] || made["uid"]
        target = deployment["target"].presence || PREVIEW_TARGET
        source = latest ? "the newest commit of its branch" : deployment["id"]
        Telemetry.result("Vercel is building #{id} for #{project['name']}, a #{target} deployment from #{source}. " \
                         "deploy_history with run #{id} follows it.", link: inspector_link(made) || project_link(environment_row, project))
      end

      # One query per metric, scoped to the project under the team that owns it (accountId on the project).
      def query_metrics(environment_row:, arguments:)
        project = find_project(environment_row, arguments["resource"])
        started, ended = Capabilities::Answers.range(arguments)
        asked = Array(arguments["metrics"]).map(&:to_s) & METRICS.keys
        asked = DEFAULT_METRICS if asked.empty?
        production = !ActiveModel::Type::Boolean.new.cast(arguments["all_environments"])
        charts = asked.map { |name| metric_chart(environment_row, project, name, started, ended, production) }
        where = production ? "production" : "every environment"
        Telemetry.result("#{project['name']}, #{where}\n#{Telemetry.charts_text(charts)}", charts: charts, link: observability_link(environment_row, project))
      rescue VercelApi::PlanLimited, VercelApi::Refused => error
        fail! Sentence.join("Vercel did not read the metrics of #{project ? project['name'] : 'this project'}", error, after: OBSERVABILITY_PLUS)
      end

      def rolling_release(environment_row:, arguments:)
        project = find_project(environment_row, arguments["resource"])
        release = api(environment_row).rolling_release(project["id"])
        link = project_link(environment_row, project)
        return Telemetry.result("#{project['name']} has had no rolling release.", link: link) unless release.is_a?(Hash)

        Telemetry.result(rolling_lines(project, release).compact.join("\n"), link: link)
      end

      # The stage after the active one, as approveRollingReleaseStage takes it.
      def advance_rolling_release(environment_row:, arguments:)
        project, release = active_rolling_release(environment_row, arguments)
        following = release["nextStage"] || fail!("The rolling release of #{project['name']} is at its last stage. complete_rolling_release ends it.")
        answer = api(environment_row).approve_rolling_stage(project["id"], next_index: following["index"], canary_id: release.dig("canaryDeployment", "id"))
        now = answer.is_a?(Hash) ? answer["rollingRelease"] : nil
        said = if following["isFinalStage"] || now.is_a?(Hash) && now["state"] == ROLLING_COMPLETE
          "#{release.dig('canaryDeployment', 'id')} now serves all production traffic of #{project['name']}, and the rolling release is complete."
        else
          "The rolling release of #{project['name']} moved to stage #{following['index'] + 1}, #{following['targetPercentage']}% of production traffic to #{release.dig('canaryDeployment', 'id')}."
        end
        Telemetry.result("#{said} abort_rolling_release goes back to #{release.dig('currentDeployment', 'id')} while it is active.", link: project_link(environment_row, project))
      end

      def complete_rolling_release(environment_row:, arguments:)
        project, release = active_rolling_release(environment_row, arguments)
        canary = release.dig("canaryDeployment", "id")
        api(environment_row).complete_rolling_release(project["id"], canary_id: canary)
        Telemetry.result("#{canary} now serves all production traffic of #{project['name']}, and the rolling release is complete. " \
                         "rollback_deployment to #{release.dig('currentDeployment', 'id')} goes back.", link: project_link(environment_row, project))
      end

      # Vercel stops a rolling release through an instant rollback to the deployment it replaces (docs, rolling-releases,
      # Stopping a rolling release with the API or SDK).
      def abort_rolling_release(environment_row:, arguments:)
        project, release = active_rolling_release(environment_row, arguments)
        base = release.dig("currentDeployment", "id") || fail!("Vercel names no deployment the rolling release of #{project['name']} replaces, so there is nothing to go back to.")
        api(environment_row).rollback(project["id"], base, description: "Rolling release stopped")
        Telemetry.result("Vercel is sending all production traffic of #{project['name']} back to #{base}, which stops the rolling release of " \
                         "#{release.dig('canaryDeployment', 'id')}. New deployments no longer go live on their own until one is promoted with promote_deployment.",
                         link: project_link(environment_row, project))
      end

      def ci_runs(environment_row:, arguments:)
        return one_ci_run(environment_row, arguments["run"].to_s.strip) if arguments["run"].present?

        limit = [ Capabilities::Answers.limit(arguments, CI_LIMIT), CI_LIMIT_MAX ].min
        answer = api(environment_row).ci_invocations(limit: limit, repository: arguments["repository"].presence, branch: arguments["branch"].presence)
        repositories = answer["repositories"].to_h
        runs = Array(answer["invocations"]).map { |invocation| ci_run(invocation, repositories) }
        Capabilities::History.result(runs, what: "Vercel CI", link: team_link(environment_row), name: arguments["name"])
      end

      def ci_job_log(environment_row:, arguments:)
        run = arguments["run"].to_s.strip.presence || fail!("Say which run, by the id ci_runs shows.")
        tree = ci_tree(environment_row, run)
        wanted = arguments["job"].to_s.strip
        job = Array(tree["jobs"]).find { |each| [ each.dig("definition", "jobDefinitionId"), each.dig("definition", "name") ].include?(wanted) } ||
              fail!("Run #{run} has no job #{wanted}. ci_runs with run #{run} lists its jobs.")
        attempt = job.dig("run", "attempt") || fail!("Job #{wanted} of run #{run} has not started, so it has no log yet.")
        lines = api(environment_row).ci_job_logs(run, attempt: tree.dig("invocation", "attempt"), job_definition_id: job.dig("definition", "jobDefinitionId"), run_attempt: attempt)
        kept = lines.filter_map do |line|
          next unless wanted?(line["message"], arguments)

          Telemetry::LogLine.new(at: millis(line["timestamp"]) || Time.current, source: line["level"].to_s, text: line["message"])
        end
        limit = Capabilities::Answers.limit(arguments, LOG_LIMIT)
        text = Telemetry.logs_text(kept.last(limit).reverse, asked: "job #{job.dig('definition', 'name')} of run #{run}", limit: kept.size > limit ? limit : limit + 1)
        Telemetry.result(text, link: team_link(environment_row))
      end

      # A GET the read guard let through (ReadGuards::Vercel), always in the team the call reaches, since the client names
      # that team on every request whatever the query says, and never on another team the path or answer names.
      def api_read(environment_row:, arguments:)
        call = begin
          ReadGuards::Vercel.reading(ApiReads::TOOL, arguments)
        rescue ReadGuards::Refused => error
          fail!(error.message)
        end
        path, query = call.values_at("path", "query")
        api = api(environment_row)
        outside_team!(environment_row, path_teams(path))

        answer = api.read(path, query)
        outside_team!(environment_row, path.match?(TEAMS_LIST) && answer.is_a?(Hash) ? Array(answer["teams"]).filter_map { |team| team["id"] if team.is_a?(Hash) } : [])

        shown = hide_bypass(answer)
        text = ApiReads.answer(PROVIDER, ApiReads.asked(path, query), shown, secret: ReadGuards::Vercel.secret?(path))
        Telemetry.result(text, link: read_link(environment_row, path, answer))
      end

      # A path naming a team by its id, and the list of the token's teams.
      TEAM_PATH = %r{\A/v\d+/teams/([^/]+)}
      TEAMS_LIST = %r{\A/v\d+/teams\z}
      PROJECT_PATH = %r{\A/v\d+/projects/([^/]+)}
      DEPLOYMENT_PATH = %r{\A/v\d+/deployments/([^/]+)/}
      # A project's protection bypass is keyed by its secret, which lets anyone past Deployment Protection (spec, getProject
      # protectionBypass), so it is hidden whole.
      BYPASS = "protectionBypass".freeze

      def path_teams(path) = path.match(TEAM_PATH)&.captures.to_a

      # A team the connection does not read, named by the path or answered by the list of teams, refused by Firefight's
      # rule. A connection that names no team reads the token's own account only.
      def outside_team!(environment_row, named)
        return if named.empty?

        settings = ConnectionSettings.of(environment_row)
        reason = if settings.chosen_scopes.empty?
          "This connection reads the token's own account only, and the read reaches team #{named.to_sentence}. Connect that team to read it."
        else
          ApiReads.outside_scopes(settings, named, "teams")
        end
        fail_policy!(reason) if reason
      end
      private :path_teams, :outside_team!

      def hide_bypass(value)
        case value
        when Hash then value.to_h { |key, inner| [ key, key == BYPASS ? ApiReads::HIDDEN : hide_bypass(inner) ] }
        when Array then value.map { |inner| hide_bypass(inner) }
        else value
        end
      end
      private :hide_bypass

      # A deployment's own page when the answer is one (inspectorUrl) or the path reads inside one, such as its events, the
      # project's page when the path reads inside one, and the team's page otherwise.
      def read_link(environment_row, path, answer)
        return inspector_link(answer) if answer.is_a?(Hash) && answer["inspectorUrl"].present?

        inside = path.match(DEPLOYMENT_PATH)&.captures&.first
        page = inside && inspector_link(api(environment_row).deployment(inside))
        return page if page

        named = path.match(PROJECT_PATH)&.captures&.first
        project = named && (answer.is_a?(Hash) && [ answer["id"], answer["name"] ].include?(named) ? answer : projects(environment_row).find { |each| [ each["id"], each["name"] ].include?(named) })
        project ? project_link(environment_row, project) : team_link(environment_row)
      rescue VercelApi::Error
        team_link(environment_row)
      end
      private :read_link

      # The team's projects on the resource map, each with the repository it builds from and the verified domains it
      # serves. What could not be read for one project is a gap, not a failed sweep.
      def map_of(environment_row)
        map_of_scopes(environment_row, kinds: MAP_KINDS) { |pack| pack.map_of_team(environment_row) }
      end

      # What a sweep puts on the map for one team.
      MAP_KINDS = [ ResourceMap::KIND_SITE, ResourceMap::KIND_DOMAIN, ResourceMap::KIND_REPOSITORY ].freeze

      def map_of_team(environment_row)
        api = api(environment_row)
        reading = MapReading.new
        projects(environment_row).each { |project| read_project(environment_row, api, project, reading) }
        listed = project_list(environment_row)
        if listed.incomplete?
          reading.gaps << ResourceMap::Gap.new(text: "Only the first #{listed.items.size} projects were read.", kinds: [ ResourceMap::KIND_SITE, ResourceMap::KIND_DOMAIN, ResourceMap::KIND_REPOSITORY ])
        end
        reading.snapshot
      end

      # Only the project a change named, read again as the sweep reads it, with its repository, domains and settings. Gone
      # only when Vercel answers not found for it. nil for a scope Vercel cannot narrow to, which a sweep reads.
      def map_refresh(environment_row, scope)
        return unless scope.external_id && [ nil, ResourceMap::KIND_SITE ].include?(scope.kind)
        return team_holding(environment_row, scope)&.map_refresh(environment_row, scope) if every_scope?(environment_row)

        api = api(environment_row)
        project = begin
          api.project(scope.external_id)
        rescue VercelApi::NotFound
          # A project's key is under the team it belongs to, which the event named. Without it a sweep says what is gone.
          return scope.account && ResourceMap::Snapshot.new(resources: [], gone: [ [ PROVIDER_KEY, scope.account, ResourceMap::KIND_SITE, scope.external_id ] ])
        end
        reading = MapReading.new
        read_project(environment_row, api, project, reading)
        reading.snapshot
      end

      # What map_of and map_refresh read, one project at a time.
      MapReading = Struct.new(:resources, :links, :gaps, :uses) do
        def initialize = super([], [], [], [])

        def snapshot = ResourceMap::Snapshot.new(resources: resources, links: links, gaps: gaps, uses: uses)
      end

      # One project with the repository it builds from, the verified domains it serves and its production settings, onto
      # the reading. What could not be read for it is a gap.
      def read_project(environment_row, api, project, reading)
        production = project.dig("targets", PRODUCTION) || {}
        found = ResourceMap::Found.new(
          provider: PROVIDER_KEY, account: project["accountId"].to_s, kind: ResourceMap::KIND_SITE, external_id: project["id"].to_s,
          name: project["name"].presence || project["id"].to_s, status: project["paused"] ? "paused" : production["readyState"]&.downcase,
          url: project_link(environment_row, project)&.url,
          details: { "type" => project["framework"], "branch" => project.dig("link", "productionBranch"),
                     ResourceMap::DEPLOYED_COMMIT => meta(production, COMMIT_SHA) }.compact
        )
        reading.resources << found
        reading.uses.concat(project_settings(api, project, found, environment_row.integration.workspace, reading.gaps)) unless slowed?(reading.gaps)
        repository = repository(project["link"])
        if repository
          reading.resources << repository
          reading.links << ResourceMap::FoundLink.new(from: found.key, to: repository.key, relation: ResourceMap::RELATION_BUILT_FROM)
        end
        domains = api.project_domains(project["id"])
        domains.items.select { |domain| domain["verified"] && domain["redirect"].blank? }.each do |domain|
          host = ResourceMap.domain(domain["name"])
          reading.resources << host
          reading.links << ResourceMap::FoundLink.new(from: host.key, to: found.key, relation: ResourceMap::RELATION_SERVED_BY)
        end
        if domains.incomplete?
          reading.gaps << ResourceMap::Gap.new(text: "Only the first #{domains.items.size} domains of #{project['name']} were read.", kinds: [ ResourceMap::KIND_DOMAIN ])
        end
      rescue Integrations::RateLimited
        raise
      rescue VercelApi::Error => error
        reading.gaps << ResourceMap::Gap.new(text: Sentence.join("The domains of #{project['name']} could not be read", error), kinds: [ ResourceMap::KIND_DOMAIN ])
      end
      private :read_project

      # Being asked to slow down while reading settings stops reading them, and the map's own reads go on.
      SLOWED = "Vercel asked Firefight to slow down, so the rest of the projects' settings were not read this time.".freeze
      # A variable whose value Vercel shows as written. Every other type (encrypted, sensitive, secret, system) is known
      # by its name only, and so is one Vercel marks as a secret in its newer visibility field (spec, filterProjectEnvs,
      # type and visibility).
      PLAIN = "plain".freeze
      SECRET_VISIBILITY = "secret".freeze

      # Lists a project in each team the connection reaches, or in the token's own account when it names none, so a team
      # the token can no longer reach is said on the connection.
      def billing_charges(environment_row:, arguments:)
        by = Spend.by(arguments)
        started = Spend.since(arguments, days: COST_DAYS, days_most: COST_DAYS_MAX, months: COST_MONTHS, months_most: COST_MONTHS_MAX)
        charges, cut = api(environment_row).billing_charges(from: started.to_time(:utc), to: Time.current.utc, limit: COST_ROWS)
        rows = charges.filter_map do |charge|
          start = Telemetry.parse_time(charge["ChargePeriodStart"])
          next unless start

          Spend::Row.new(period: Spend.period_of(start, by), service: charge["ServiceName"].to_s, amount: charge["BilledCost"].to_f,
                         project: charge.dig("Tags", "ProjectName").presence)
        end
        currency = charges.first&.dig("BillingCurrency") || "USD"
        note = "Vercel had more charges than Firefight read, so the newest are missing." if cut
        Telemetry.result(Spend.text(rows, by: by, since: started.iso8601, currency: currency, cut: note), link: team_link(environment_row))
      rescue VercelApi::Refused => error
        fail! Sentence.join("Vercel refused to read the team's charges. The token's role on the team needs to see billing", error)
      end

      def check_health!(environment_row)
        teams = ConnectionSettings.of(environment_row).scopes
        teams.empty? ? api(environment_row).check! : teams.each { |team| scoped(team).send(:api, environment_row).check! }
      rescue VercelApi::Error => error
        fail! error.message
      end

      private

      def api(environment_row)
        settings = ConnectionSettings.of(environment_row)
        token = settings.credential(API_TOKEN)
        fail! "This environment has no Vercel access token. Reconnect it on the Integrations page." if token.blank?

        VercelApi.new(token, team_of(environment_row))
      end

      # The team a call reaches, or nil for the token's own account when the connection names none.
      def team_of(environment_row) = scope!(environment_row)

      # A listing of every team the connection reaches, each read by a pack of its own and headed with its own.
      def every_team(environment_row)
        texts = ConnectionSettings.of(environment_row).scopes.map do |team|
          Array(yield(scoped(team))["content"]).filter_map { |part| part["text"] }.join("\n")
        end
        Telemetry.result(texts.join("\n\n"), link: nil)
      end

      # The pack of the team a change is in, the team the event named or the one the map has the project in. nil, for a
      # sweep to read, when neither is one the connection reaches.
      def team_holding(environment_row, scope)
        reached = ConnectionSettings.of(environment_row).scopes
        return scoped(scope.account) if scope.account.present? && reached.include?(scope.account)

        on_map = ResourceMap::Resource.present.where(workspace_id: environment_row.integration.workspace_id, provider: PROVIDER_KEY, external_id: scope.external_id)
                                      .where("resource_map_resources.integration_environment_id = :row OR resource_map_resources.sightings ? :row", row: environment_row.id.to_s)
                                      .pick(Arel.sql("details ->> '#{ResourceMap::SCOPE}'"))
        scoped(on_map) if on_map.present? && reached.include?(on_map)
      end

      def projects(environment_row) = project_list(environment_row).items

      # The production settings of a project, as the site runs them. The project list carries them when Vercel includes
      # env on each project (spec, getProjects), and otherwise one read per project gets them.
      def project_settings(api, project, found, workspace, gaps)
        variables = project["env"]
        unless variables.is_a?(Array)
          variables, more = api.project_env(project["id"])
          gaps << ResourceMap::Gap.new(text: "Only the first page of #{project['name']}'s settings was read.", kinds: [], settings: true) if more
        end
        production = variables.select { |variable| Array(variable["target"]).include?(PRODUCTION) }
        plain, hidden = production.partition { |variable| variable["type"] == PLAIN && variable["visibility"] != SECRET_VISIBILITY && variable.key?("value") }
        ResourceMap::Use.read(from: found.key, workspace: workspace, values: plain.to_h { |variable| [ variable["key"], variable["value"] ] },
                              names: hidden.map { |variable| variable["key"] })
      rescue Integrations::RateLimited
        gaps << ResourceMap::Gap.new(text: SLOWED, kinds: [], settings: true)
        []
      rescue VercelApi::Error => error
        gaps << ResourceMap::Gap.new(text: Sentence.join("The settings of #{project['name']} could not be read", error), kinds: [], settings: true)
        []
      end

      def slowed?(gaps) = gaps.any? { |gap| gap.text == SLOWED }

      # The team's projects, as a Pages::Read that says whether they were read to the end.
      def project_list(environment_row) = @project_list ||= api(environment_row).projects

      def find_project(environment_row, asked)
        fail! "Say which project, by name or id. list_resources shows them." if asked.to_s.strip.empty?

        rows = projects(environment_row).map { |project| { id: project["id"], name: project["name"], project: project } }
        found = Named.find(rows, asked, id: :id, name: :name, provider: PROVIDER, connection: environment_row)&.dig(:project)
        return found if found
        fail!("No project called #{asked} in this team. list_resources shows what there is.") if project_list(environment_row).complete

        project_past_list(environment_row, asked.to_s.strip) ||
          fail!("No project called #{asked} among the first #{rows.size} projects read from this team, and Vercel has none by that id or name.")
      end

      # A project past the list's cap, read by its id or name (spec, getProject). Vercel answers 404 for one it does not hold.
      def project_past_list(environment_row, asked)
        project = api(environment_row).project(asked)
        project["id"].present? ? project : nil
      rescue Integrations::RateLimited
        raise
      rescue VercelApi::Error
        nil
      end

      # The deployment asked for, or the production one, checked to be the project's own.
      def find_deployment(environment_row, project, asked, required: false)
        asked = asked.to_s.strip
        fail! "Say which deployment, by the id list_deployments shows." if asked.empty? && required

        reference = asked.presence || project.dig("targets", PRODUCTION, "id")
        fail! "#{project['name']} has no production deployment. Name one from list_deployments." if reference.blank?

        deployment = api(environment_row).deployment(reference.delete_prefix("https://"))
        unless deployment["projectId"] == project["id"]
          fail! "#{asked} is not a deployment of #{project['name']}. list_deployments shows its deployments."
        end

        deployment
      end

      def history_run(deployment)
        sha = meta(deployment, COMMIT_SHA)
        Capabilities::History::Run.new(
          id: deployment["uid"] || deployment["id"], name: "#{deployment['target'] || 'preview'} deploy",
          status: Capabilities::History.status(deployment["readyState"] || deployment["state"], DEPLOYMENT_STATES),
          started_at: millis(deployment["buildingAt"] || deployment["createdAt"] || deployment["created"]), finished_at: ended_at(deployment),
          url: deployment["inspectorUrl"],
          detail: [ ("#{sha.first(12)} #{meta(deployment, COMMIT_MESSAGE).to_s.lines.first.to_s.strip}".strip if sha), error_words(deployment) ].compact.join(", ").presence
        )
      end

      def error_words(deployment) = [ deployment["errorCode"], deployment["errorMessage"] ].compact.join(": ").presence

      # A deployment ends when it is ready, or for one that failed or was canceled, when its build failed or it was canceled,
      # which only a deployment read by its id gives (spec, getDeployment buildErrorAt and canceledAt).
      def ended_at(deployment)
        state = (deployment["readyState"] || deployment["state"]).to_s.upcase
        millis(deployment["ready"] || (deployment["buildErrorAt"] || deployment["canceledAt"] if ENDED_WITHOUT_READY.include?(state)))
      end

      # Vercel names the value of each row by the metric and aggregation with dots and slashes as underscores, as its CLI
      # reads it (packages/cli/src/commands/metrics/output.ts, getRollupColumnName).
      def metric_chart(environment_row, project, name, started, ended, production)
        metric = METRICS.fetch(name)
        filter = [ metric.filter, (PRODUCTION_FILTER if production) ].compact
        body = {
          "scope" => { "type" => "project", "ownerId" => project["accountId"], "projectIds" => [ project["id"] ] },
          "metric" => metric.metric, "aggregation" => metric.aggregation,
          "startTime" => started.utc.iso8601, "endTime" => ended.utc.iso8601, "granularity" => granularity_for(ended - started),
          "filter" => (filter.size > 1 ? filter.map { |each| "(#{each})" }.join(" and ") : filter.first)
        }.compact
        column = "#{metric.metric}_#{metric.aggregation}".tr("./", "__")
        rows = Array(api(environment_row).observability_query(body)["data"])
        points = rows.filter_map do |row|
          at = Telemetry.parse_time(row["timestamp"])
          value = Float(row[column].to_s, exception: false)
          [ at, value ] if at && value&.finite?
        end
        Telemetry::Chart.new(title: "#{metric.title} of #{project['name']}", unit: metric.unit, from: started, to: ended,
                             series: [ Telemetry::Series.new(label: project["name"], points: points.sort_by(&:first)) ],
                             link: observability_link(environment_row, project)&.url)
      end

      def granularity_for(range) = GRANULARITIES.find { |most, _granularity| range <= most }&.last || COARSEST

      # Vercel documents no address for a project's Observability page, so metrics link the project's own page, where
      # Observability is in its sidebar (docs, observability).
      def observability_link(environment_row, project) = project_link(environment_row, project)

      ROLLING_ACTIVE = "ACTIVE".freeze
      ROLLING_COMPLETE = "COMPLETE".freeze

      # The project's rolling release, refused in words unless one is active.
      def active_rolling_release(environment_row, arguments)
        project = find_project(environment_row, arguments["resource"])
        release = api(environment_row).rolling_release(project["id"])
        unless release.is_a?(Hash) && release["state"] == ROLLING_ACTIVE
          fail! "#{project['name']} has no rolling release in progress#{", its last one is #{release['state'].to_s.downcase}" if release.is_a?(Hash)}. rolling_release shows it."
        end

        [ project, release ]
      end

      def rolling_lines(project, release)
        canary = release["canaryDeployment"].to_h
        current = release["currentDeployment"].to_h
        stage = release["activeStage"]
        [
          "Rolling release of #{project['name']}: #{release['state'].to_s.downcase}#{', paused' if release['substate'] == 'PAUSED'}, " \
          "#{release['advancementType'] == 'manual-approval' ? 'each stage waits for approval' : 'stages move on their own'}",
          ("Rolling out #{canary['id']}, #{canary['readyState'].to_s.downcase}" if canary.any?),
          ("Replacing #{current['id']}" if current.any?),
          (stage ? "At stage #{stage['index'] + 1} of #{Array(release['stages']).size}, #{release['currentCanaryPercentage'] || stage['targetPercentage']}% of production traffic to the new deployment" : nil),
          (stage_line("Next", release["nextStage"]) if release["nextStage"]),
          ("Started #{millis(release['startedAt'])&.iso8601}, last changed #{millis(release['updatedAt'])&.iso8601}" if release["startedAt"]),
          ("Queued to roll out next: #{release['queuedDeploymentId']}" if release["queuedDeploymentId"].present?)
        ]
      end

      def stage_line(label, stage)
        timing = if stage["requireApproval"] then "waits for approval"
        elsif stage["duration"] then "moves on after #{stage['duration'].to_i / 60} minutes"
        end
        "#{label}: stage #{stage['index'] + 1}, #{stage['targetPercentage']}% of traffic#{", #{timing}" if timing}#{', the last' if stage['isFinalStage']}"
      end

      # Vercel CI's invocation statuses and conclusions (spec, listVercelCiInvocations status, completed.conclusion and
      # runConclusion.result) in Firefight's words.
      CI_RESULTS = {
        "succeeded" => Capabilities::History::SUCCEEDED, "failed" => Capabilities::History::FAILED, "skipped" => Capabilities::History::CANCELLED,
        "cached" => Capabilities::History::SUCCEEDED
      }.freeze
      CI_FAILED = %w[bootstrapping_failed jobs_on_hive_failed].freeze
      CI_SKIPPED = "skipped".freeze
      CI_NEW = "new".freeze

      def ci_status(invocation)
        result = invocation.dig("completed", "conclusion") || invocation.dig("runConclusion", "result")
        return Capabilities::History.status(result, CI_RESULTS) if invocation["completed"].is_a?(Hash) && result
        return Capabilities::History::FAILED if CI_FAILED.include?(invocation["status"])
        return Capabilities::History::CANCELLED if invocation["status"] == CI_SKIPPED
        return Capabilities::History::QUEUED if invocation["status"] == CI_NEW

        Capabilities::History::RUNNING
      end

      def ci_run(invocation, repositories)
        repository = repositories[invocation["repositoryKey"]].to_h
        named = [ repository["owner"], repository["name"] ].compact.join("/").presence || invocation["repositoryKey"]
        Capabilities::History::Run.new(
          id: invocation["invocationId"], name: "CI #{named}", status: ci_status(invocation),
          started_at: millis(invocation.dig("bootstrappingStarted", "startedAt") || invocation["createdAt"]),
          finished_at: millis(invocation.dig("completed", "completedAt")),
          detail: [ ("#{invocation['ref']} at #{invocation['commitSha'].to_s.first(12)}" if invocation["ref"].present?), ("attempt #{invocation['attempt']}" if invocation["attempt"].to_i > 1),
                    invocation.dig("bootstrappingFailed", "reason"), invocation.dig("skipped", "reason") ].compact.join(", ").presence
        )
      end

      def ci_tree(environment_row, run)
        api(environment_row).ci_invocation_tree(run)
      rescue VercelApi::NotFound
        fail! "Vercel CI has no run #{run} in this team. ci_runs lists its runs."
      end

      # One run read by its id with each job as a part, its log read by ci_job_log.
      def one_ci_run(environment_row, run)
        tree = ci_tree(environment_row, run)
        parts = Array(tree["jobs"]).map do |job|
          job_run = job["run"].to_h
          conclusion = job_run.dig("completed", "conclusion").to_h
          status = if conclusion["result"] then Capabilities::History.status(conclusion["result"], CI_RESULTS)
          elsif job_run["started"] then Capabilities::History::RUNNING
          else Capabilities::History::QUEUED
          end
          Capabilities::History::Part.new(
            id: job.dig("definition", "jobDefinitionId"), name: job.dig("definition", "name"), status: status,
            started_at: millis(job_run.dig("started", "startedAt")), finished_at: millis(job_run.dig("completed", "completedAt")),
            detail: conclusion["reason"].presence,
            log: { Capabilities::History::LOG_TOOL => "ci_job_log",
                   Capabilities::History::LOG_ARGUMENTS => { "run" => run, "job" => job.dig("definition", "jobDefinitionId") } }
          )
        end
        found = ci_run(tree["invocation"].to_h, tree["repositories"].to_h).with(parts: parts)
        Capabilities::History.result([ found ], what: "Vercel CI", link: team_link(environment_row))
      end

      # One deployment read by its id (spec, getDeployment), with its build and, where the project runs them, its checks as
      # parts. The build's log is read for this deployment by deployment_logs, never the newest one's.
      def one_deployment(environment_row, project, given)
        deployment = begin
          find_deployment(environment_row, project, given.to_s.strip.delete_prefix("#"), required: true)
        rescue VercelApi::NotFound
          fail! "#{project['name']} has no deployment #{given}. deploy_history lists its deployments."
        end
        run = history_run(deployment).with(parts: [ build_part(project, deployment), checks_part(deployment) ].compact)
        Capabilities::History.result([ run ], what: project["name"], link: inspector_link(deployment) || project_link(environment_row, project))
      end

      # Vercel's check states and conclusions (spec, getDeployment checksState, checksConclusion and checks) in Firefight's words.
      CHECK_STATES = {
        "registered" => Capabilities::History::QUEUED, "running" => Capabilities::History::RUNNING, "pending" => Capabilities::History::RUNNING,
        "succeeded" => Capabilities::History::SUCCEEDED, "skipped" => Capabilities::History::SUCCEEDED,
        "failed" => Capabilities::History::FAILED, "canceled" => Capabilities::History::CANCELLED
      }.freeze
      CHECKS_DONE = "completed".freeze
      ALIAS_CHECK = "deployment-alias".freeze

      # The build runs from buildingAt until the deployment is ready or fails, and errorStep names the step it failed at.
      def build_part(project, deployment)
        id = deployment["uid"] || deployment["id"]
        detail = [ ("at #{deployment['errorStep']}" if deployment["errorStep"].present?), error_words(deployment),
                   ("out of memory" if deployment["oomReport"].present?) ].compact.join(", ").presence
        Capabilities::History::Part.new(
          id: "#{id}/build", name: "build", status: Capabilities::History.status(deployment["readyState"] || deployment["state"], DEPLOYMENT_STATES),
          started_at: millis(deployment["buildingAt"] || deployment["createdAt"]), finished_at: ended_at(deployment),
          url: deployment["inspectorUrl"], detail: detail,
          log: { Capabilities::History::LOG_TOOL => "deployment_logs",
                 Capabilities::History::LOG_ARGUMENTS => { "resource" => project["id"], "deployment" => id, "type" => BUILD } }
        )
      end

      # The checks that gate a deployment's promotion, only when the project runs any.
      def checks_part(deployment)
        state = deployment["checksState"].to_s.downcase
        return if state.empty?

        timed = deployment.dig("checks", ALIAS_CHECK).to_h
        status = Capabilities::History.status(state == CHECKS_DONE ? deployment["checksConclusion"] : state, CHECK_STATES)
        Capabilities::History::Part.new(
          id: "#{deployment['uid'] || deployment['id']}/checks", name: "checks", status: status, started_at: millis(timed["startedAt"]),
          finished_at: (millis(timed["completedAt"]) if Capabilities::History::FINISHED.include?(status)), url: deployment["inspectorUrl"]
        )
      end

      def latest_id(environment_row, project)
        latest = api(environment_row).deployments(project["id"], limit: 1).first
        latest && (latest["uid"] || latest["id"])
      end

      def build_logs(environment_row, project, deployment, arguments, limit)
        events = api(environment_row).deployment_events(deployment["id"], limit: limit)
        lines = events.filter_map do |event|
          payload = event["payload"].is_a?(Hash) ? event["payload"] : event
          next unless OUTPUT_EVENTS.include?(event["type"]) && payload["text"].present?

          at = millis(payload["date"] || event["created"])
          Telemetry::LogLine.new(at: at || Time.current, source: event["type"], text: payload["text"]) if wanted?(payload["text"], arguments)
        end
        error = [ deployment["errorCode"], deployment["errorMessage"] ].compact.join(": ").presence
        head = error ? "#{deployment['id']} failed: #{error}#{" (#{deployment['errorStep']})" if deployment['errorStep']}\n" : ""
        oom = deployment["oomReport"].present? ? "Vercel reports the build ran out of memory.\n" : ""
        text = Telemetry.logs_text(lines, asked: "the build of #{deployment['id']}", limit: lines.size >= limit ? lines.size : limit)
        Telemetry.result("#{head}#{oom}#{text}", link: inspector_link(deployment) || project_link(environment_row, project))
      end

      def runtime_logs(environment_row, project, deployment, arguments, limit)
        seconds = arguments["seconds"].to_i.positive? ? [ arguments["seconds"].to_i, MAX_SECONDS ].min : DEFAULT_SECONDS
        rows = api(environment_row).runtime_logs(project["id"], deployment["id"], seconds: seconds, limit: limit)
        lines = rows.filter_map do |row|
          text = [ row["level"], row["requestMethod"], row["requestPath"], row["responseStatusCode"], row["message"] ].compact.join(" ")
          next unless wanted?(text, arguments)

          Telemetry::LogLine.new(at: millis(row["timestampInMs"]) || Time.current, source: row["source"].to_s, text: text)
        end.reverse
        watched = "#{deployment['id']}, watched live for up to #{seconds} seconds"
        note = "Vercel's API gives runtime logs only as they happen, so these are the lines logged while watching. Earlier " \
               "lines are on the project's Logs page, which keeps them #{RETENTION}."
        text = Telemetry.logs_text(lines, asked: watched, limit: rows.size >= limit ? lines.size : limit + 1)
        Telemetry.result("#{text}\n#{note}", link: logs_link(environment_row, project))
      end

      def wanted?(text, arguments)
        include = arguments["text"].to_s
        exclude = arguments["exclude"].to_s
        (include.empty? || text.to_s.include?(include)) && (exclude.empty? || !text.to_s.include?(exclude))
      end

      def deployment_line(deployment, current: nil)
        id = deployment["uid"] || deployment["id"]
        sha = meta(deployment, COMMIT_SHA)
        message = meta(deployment, COMMIT_MESSAGE).to_s.lines.first.to_s.strip
        created = millis(deployment["createdAt"] || deployment["created"])&.iso8601
        error = [ deployment["errorCode"], deployment["errorMessage"] ].compact.join(": ").presence
        [ created, id, deployment["target"] || "preview", (deployment["readyState"] || deployment["state"]).to_s.downcase,
          deployment["readySubstate"]&.downcase, ("serving production now" if current && id == current),
          ("#{sha.first(12)} \"#{message}\"" if sha), ("on #{meta(deployment, COMMIT_REF)}" if meta(deployment, COMMIT_REF)),
          ("by #{deployment.dig('creator', 'username')}" if deployment.dig("creator", "username")),
          ("failed: #{error}" if error), ("ran out of memory" if deployment["oomReport"].present?),
          ("page #{deployment['inspectorUrl']}" if deployment["inspectorUrl"]) ].compact.join(", ")
      end

      def alias_request_line(request)
        return nil unless request.is_a?(Hash)

        at = millis(request["requestedAt"])&.iso8601
        "Last #{request['type']}: to #{request['toDeploymentId']} from #{request['fromDeploymentId']}, #{request['jobStatus']}#{", asked #{at}" if at}" \
          "#{'. New deployments do not go live on their own until one is promoted' if request['type'] == 'rollback'}"
      end

      def repository_line(link)
        return "Git: not connected" unless link.is_a?(Hash)

        repository = link["repo"] ? "#{link['org']}/#{link['repo']}" : link["projectNameWithNamespace"] || link["slug"]
        "Git: #{link['type']} #{repository}, production branch #{link['productionBranch'] || 'unknown'}"
      end

      def domain_words(domain)
        [ domain["name"], ("redirects to #{domain['redirect']}" if domain["redirect"].present?), ("branch #{domain['gitBranch']}" if domain["gitBranch"]),
          ("not verified" unless domain["verified"]) ].compact.join(", ")
      end

      # The repository a project builds from. Vercel's link types are the registry's keys of the code hosts it links to.
      def repository(link)
        return nil unless link.is_a?(Hash) && link["org"].present? && link["repo"].present?

        ResourceMap.repository(link["type"], "#{link['org']}/#{link['repo']}")
      end

      def meta(deployment, keys) = keys.filter_map { |key| deployment.to_h.dig("meta", key).presence }.first

      def millis(value) = value.is_a?(Numeric) ? Time.zone.at(value / 1000.0).utc : Telemetry.parse_time(value)

      def inspector_link(deployment) = deployment["inspectorUrl"].present? ? Telemetry::Link.new(provider: PROVIDER, url: deployment["inspectorUrl"]) : nil

      # A project's page, https://vercel.com/<team slug>/<project name>, as Vercel's CLI opens it (commands/open/index.ts).
      # Without a known slug there is no page to name.
      def project_link(environment_row, project)
        slug = owner_slug(environment_row)
        slug ? Telemetry::Link.new(provider: PROVIDER, url: "#{ConnectionSettings.of(environment_row).site}/#{ERB::Util.url_encode(slug)}/#{ERB::Util.url_encode(project['name'])}") : nil
      end

      # The team's page, https://vercel.com/<team slug>, the address Vercel's CLI calls a team's URL (commands/teams/add.ts).
      def team_link(environment_row)
        slug = owner_slug(environment_row)
        slug ? Telemetry::Link.new(provider: PROVIDER, url: "#{ConnectionSettings.of(environment_row).site}/#{ERB::Util.url_encode(slug)}") : nil
      end

      # The project's Logs page, the address Vercel's docs open as /[team]/[project]/logs (docs, logs/runtime).
      def logs_link(environment_row, project)
        page = project_link(environment_row, project)
        page && Telemetry::Link.new(provider: "#{PROVIDER}, on the Logs page", url: "#{page.url}/logs")
      end

      # The slug the dashboard uses: the team's, read from Vercel when the team is given by id, or the person's username
      # for a personal account. nil when Vercel will not say.
      def owner_slug(environment_row)
        return @owner_slug if defined?(@owner_slug)

        team = team_of(environment_row).to_s.strip
        @owner_slug = if team.match?(VercelApi::TEAM_ID) then api(environment_row).team(team)["slug"].presence
        elsif team.present? then team
        else api(environment_row).user["username"].presence
        end
      rescue Integrations::RateLimited
        raise
      rescue VercelApi::Error
        @owner_slug = nil
      end
    end
  end
end
