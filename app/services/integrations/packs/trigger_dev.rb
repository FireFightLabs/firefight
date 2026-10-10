module Integrations
  module Packs
    # Trigger.dev for one project environment per environment row: its tasks, their runs and what they logged, error
    # groups, queues, deployments and the metrics Trigger.dev keeps, read with that environment's secret API key. Every
    # tool reads, except promote_deployment, which makes an earlier version the current one. The paths, parameters and
    # fields are the ones in Trigger.dev's OpenAPI spec (triggerdotdev/trigger.dev, docs/v3-openapi.yaml), and the
    # queries the ones its query docs give (docs/observability/query.mdx, docs/logging.mdx).
    class TriggerDev < NativePack
      # The environment row's credentials, which only this pack reads.
      API_KEY = "api_key".freeze
      PROJECT = "project".freeze

      PROVIDER = "Trigger.dev".freeze
      PROVIDER_KEY = "trigger_dev".freeze
      PROJECT_REF = /\Aproj_[a-z0-9]+\z/
      KEY_PREFIX = "tr_".freeze
      # A secret key names its environment's slug after the prefix, such as prod in tr_prod_sk_.
      KEY_ENVIRONMENT = /\Atr_([a-z]+)_/

      # A run's status, as the runs API names it (CommonRunsFilter).
      RUN_STATUSES = %w[PENDING_VERSION QUEUED EXECUTING REATTEMPTING FROZEN COMPLETED CANCELED FAILED CRASHED INTERRUPTED SYSTEM_FAILURE].freeze
      FAILED_STATUSES = %w[FAILED CRASHED SYSTEM_FAILURE].freeze
      WAITING_STATUSES = %w[PENDING_VERSION QUEUED].freeze
      HISTORY_STATUSES = {
        "pending_version" => Capabilities::History::QUEUED, "queued" => Capabilities::History::QUEUED, "delayed" => Capabilities::History::QUEUED,
        "executing" => Capabilities::History::RUNNING, "reattempting" => Capabilities::History::RUNNING, "frozen" => Capabilities::History::RUNNING,
        "completed" => Capabilities::History::SUCCEEDED, "failed" => Capabilities::History::FAILED, "crashed" => Capabilities::History::FAILED,
        "system_failure" => Capabilities::History::FAILED, "interrupted" => Capabilities::History::FAILED, "timed_out" => Capabilities::History::FAILED,
        "canceled" => Capabilities::History::CANCELLED, "expired" => Capabilities::History::CANCELLED
      }.freeze
      DEPLOYED = "DEPLOYED".freeze
      DEPLOYMENT_STATUSES = %w[PENDING BUILDING DEPLOYING DEPLOYED FAILED CANCELED TIMED_OUT].freeze
      ERROR_STATUSES = %w[unresolved resolved ignored].freeze

      # What the query API reads for each metric. Runs and their status come from the runs table, CPU and memory from the
      # metrics Trigger.dev collects for deployed tasks (process.cpu.utilization, a ratio, and process.memory.usage, in
      # bytes). Failed and Crashed are the failed statuses its query docs use.
      METRICS = %w[requests errors cpu memory].freeze
      DEFAULT_METRICS = %w[requests errors].freeze
      COUNTED = %w[requests errors].freeze
      RUNTIME_METRICS = { "cpu" => "process.cpu.utilization", "memory" => "process.memory.usage" }.freeze
      METRIC_TITLES = { "requests" => "Runs started", "errors" => "Failed runs", "cpu" => "CPU", "memory" => "Memory" }.freeze
      METRIC_UNITS = { "cpu" => "%", "memory" => "MB" }.freeze
      PER_MINUTE = "per minute".freeze
      COUNT = "count".freeze
      TASK_QUEUE = "task".freeze
      QUERY_ROWS = 10_000
      # A task's identifier goes into a query as a quoted string, so only the characters a task id is made of are taken.
      TASK_ID = %r{\A[A-Za-z0-9_.:/-]+\z}
      VERSION = /\A[A-Za-z0-9_.-]+\z/

      RUN_LIMIT = 50
      LOG_LIMIT = 200
      LOG_RUNS = 10
      DEPLOYMENT_LIMIT = 20
      ERROR_LIMIT = 50
      STACK_LINES = 8
      MESSAGE_LIMIT = 2_000
      NANOSECONDS = 1_000_000_000.0

      RANGE = Capabilities::RANGE
      TASK = { "type" => "string", "description" => "A task, by its identifier, as list_tasks shows it" }.freeze

      tool :list_tasks,
           description: "The tasks in the newest version deployed to this Trigger.dev environment, with the file each is defined in. " \
                        "Use it first to find the identifier to pass to the other tools",
           params_schema: { "type" => "object", "properties" => {} },
           read_only: true

      tool :list_runs,
           description: "Runs in this environment, newest first, with each run's id, task, status, version, when it was created, " \
                        "started and finished, and how long it computed. Filter by task, status, the error group it belongs to " \
                        "and when it was created",
           params_schema: {
             "type" => "object",
             "properties" => {
               "task" => { "type" => "string", "description" => "Only runs of this task, by its identifier (optional)" },
               "status" => { "type" => "array", "items" => { "type" => "string", "enum" => RUN_STATUSES },
                             "description" => "Only runs in these states (optional)" },
               "error" => { "type" => "string", "description" => "Only the runs behind this error group, by its id from list_errors (optional)" },
               "limit" => { "type" => "integer", "description" => "At most this many runs (optional, #{RUN_LIMIT})" },
               **RANGE
             }
           },
           read_only: true

      tool :run_details,
           description: "One run: its status, task, version, timings, every attempt with its error and stack, the runs around it, and what " \
                        "it logged. The payload and output are left out, since they can hold customer data",
           params_schema: { "type" => "object", "properties" => { "run" => { "type" => "string", "description" => "The run's id, starting run_" } },
                            "required" => [ "run" ] },
           read_only: true

      tool :search_task_logs,
           description: "What a task's recent runs logged, newest first, at most #{LOG_LIMIT} lines from its latest #{LOG_RUNS} runs in the " \
                        "range. Filter by text or a regular expression",
           params_schema: {
             "type" => "object",
             "properties" => {
               "task" => TASK,
               "text" => { "type" => "string", "description" => "Only lines containing this text (optional)" },
               "regex" => { "type" => "string", "description" => "Only lines matching this regular expression (optional)" },
               "exclude" => { "type" => "string", "description" => "Leave out lines containing this text (optional)" },
               "status" => { "type" => "array", "items" => { "type" => "string", "enum" => RUN_STATUSES },
                             "description" => "Only runs in these states, such as FAILED (optional)" },
               "limit" => { "type" => "integer", "description" => "At most this many lines (optional, #{LOG_LIMIT})" },
               **RANGE
             },
             "required" => [ "task" ]
           },
           read_only: true

      tool :describe_task,
           description: "How one task stands now: the version deployed to the environment and where the task is defined in it, its " \
                        "queue (running, queued, paused and its concurrency limit), and how its runs in the last hour ended",
           params_schema: { "type" => "object", "properties" => { "task" => TASK }, "required" => [ "task" ] },
           read_only: true

      tool :list_deployments,
           description: "The environment's deployments, newest first: the version, its status, when it was created and deployed, its " \
                        "git details and why it failed. A version is what promote_deployment takes. Every task in the environment " \
                        "runs the same version",
           params_schema: {
             "type" => "object",
             "properties" => {
               "status" => { "type" => "string", "enum" => DEPLOYMENT_STATUSES, "description" => "Only deployments in this state (optional)" },
               "limit" => { "type" => "integer", "description" => "At most this many deployments (optional, #{DEPLOYMENT_LIMIT})" }
             }
           },
           read_only: true

      tool :list_errors,
           description: "Error groups in this environment, most frequent first: the error's type and message, the task, how often it " \
                        "happened in the range, when it was first and last seen, and whether it is resolved. Pass an error's id to " \
                        "list_runs to see the runs behind it",
           params_schema: {
             "type" => "object",
             "properties" => {
               "task" => { "type" => "string", "description" => "Only errors of this task, by its identifier (optional)" },
               "text" => { "type" => "string", "description" => "Only errors whose type or message contains this text (optional)" },
               "status" => { "type" => "array", "items" => { "type" => "string", "enum" => ERROR_STATUSES },
                             "description" => "Only error groups in these states (optional, every state)" },
               "limit" => { "type" => "integer", "description" => "At most this many error groups (optional, #{ERROR_LIMIT})" },
               **RANGE
             }
           },
           read_only: true

      tool :list_queues,
           description: "The environment's queues and concurrency limits: for each, how many runs are executing and waiting, whether " \
                        "it is paused, and its limit. Runs piling up behind a paused queue or a full limit show here",
           params_schema: { "type" => "object", "properties" => {} },
           read_only: true

      tool :task_metrics,
           description: "Metrics of one task over time: runs started, failed runs, and the CPU and memory of its runs. Returns min, " \
                        "average, max and latest, and the person sees each metric as a chart",
           params_schema: {
             "type" => "object",
             "properties" => {
               "task" => TASK,
               "metrics" => { "type" => "array", "items" => { "type" => "string", "enum" => METRICS },
                              "description" => "Which metrics (optional, #{DEFAULT_METRICS.join(', ')})" },
               **RANGE
             },
             "required" => [ "task" ]
           },
           read_only: true

      tool :promote_deployment,
           description: "Make an earlier deployed version the current one for this environment, which rolls every task in it back. New " \
                        "runs start on that version, and runs already started keep the version they started on",
           params_schema: {
             "type" => "object",
             "properties" => { "version" => { "type" => "string", "description" => "The version to promote, such as 20250228.1, as list_deployments shows it" } },
             "required" => [ "version" ]
           },
           read_only: false

      tool :api_read,
           description: "Anything else Trigger.dev's API reads that the other tools do not cover, such as one deployment or batch, " \
                        "a run's result or attempts, schedules, waitpoints, bulk actions or concurrency limits. A GET to a path of " \
                        "the API (#{TriggerDevApi::API_ROOT}), written as the API reference the trigger_dev_api skill names writes " \
                        "it, starting /api. A list answers one page: pass page[size] and, for the next, page[after] set to the " \
                        "answer's pagination next. Only reads, so it never changes anything. Environment variables come back as their names",
           params_schema: ApiReads.path_schema("/api/v1/schedules"),
           read_only: true

      def self.credential_fields
        [
          CredentialField.new(key: API_KEY, label: "Secret API key", secret: true, placeholder: "tr_prod_sk_...",
                              hint: "A named API key of the environment this connection reads, from API keys in the Trigger.dev dashboard. " \
                                    "Observer reads runs, logs and queues. For Halon to promote an earlier version, choose a preset " \
                                    "that can deploy, such as No restrictions.")
        ]
      end

      # Reads the environment's runs with the key, so a wrong key is said on the form before anything is saved.
      def self.credential_refusal(values, region: nil, fields: {})
        key = values[API_KEY].to_s.strip
        project = fields.to_h.stringify_keys[PROJECT].to_s.strip
        return "Paste a secret API key." if key.empty?
        return "That is not a Trigger.dev secret API key. It starts with tr_, such as tr_prod_sk_." unless key.start_with?(KEY_PREFIX)
        return "Enter the project ref, which starts with proj_." unless project.match?(PROJECT_REF)

        TriggerDevApi.new(key).runs(limit: TriggerDevApi::MIN_RUN_PAGE)
        nil
      rescue TriggerDevApi::Error => error
        Sentence.join("Trigger.dev refused this key", error, after: "Check it belongs to the environment you chose and can read runs")
      end

      def self.store_credentials!(environment_row, values)
        environment_row.store_credential!(API_KEY, values[API_KEY].to_s.strip)
      end

      def list_tasks(environment_row:, arguments:)
        deployment = deployed_version(environment_row)
        return Telemetry.result(no_deployment, link: nil) unless deployment

        tasks = Array(deployment.dig("worker", "tasks"))
        rows = tasks.map { |task| [ task["slug"], ("in #{task['filePath']}" if task["filePath"].present?) ].compact.join(" ") }
        return Telemetry.result("Version #{deployment['version']} has no tasks. #{no_page}", link: nil) if rows.empty?

        Telemetry.result("Version #{deployment['version']}, the newest deployed to this environment, has #{rows.size} tasks.\n#{rows.join("\n")}\n#{no_page}",
                         link: nil)
      end

      def list_runs(environment_row:, arguments:)
        started, ended = Capabilities::Answers.range(arguments)
        runs = api(environment_row).runs(filter: run_filter(arguments, started, ended).merge("error" => arguments["error"].presence),
                                         limit: Capabilities::Answers.limit(arguments, RUN_LIMIT))
        asked = [ ("of #{arguments['task']}" if arguments["task"].present?), "created from #{started.utc.iso8601} to #{ended.utc.iso8601}" ].compact.join(" ")
        return Capabilities::RunHistory.with_runs(Telemetry.result("No runs #{asked}.", link: nil), []) if runs.empty?

        rows = runs.map { |run| run_line(environment_row, run) }
        link = run_link(environment_row, runs.first["id"])
        result = Telemetry.result("#{rows.size} runs #{asked}, newest first. Each ends with its page in Trigger.dev.\n#{rows.join("\n")}", link: link)
        Capabilities::RunHistory.with_runs(result, runs.map { |run| history_run(environment_row, run) }, link: link)
      end

      def run_details(environment_row:, arguments:)
        id = arguments["run"].to_s.strip
        fail! "Say which run, by its id starting run_. list_runs shows them." if id.empty?

        run = api(environment_row).run(id)
        events = api(environment_row).run_events(id)
        lines = [
          "Run #{run['id']} of #{run['taskIdentifier']}, #{run['status']}, version #{run['version'] || 'unknown'}",
          "Created #{run['createdAt']}, started #{run['startedAt'] || 'not yet'}, finished #{run['finishedAt'] || 'not yet'}, computed #{run['durationMs'] || 0} ms",
          ("Tags: #{Array(run['tags']).join(', ')}" if Array(run["tags"]).any?),
          related_line(run["relatedRuns"]),
          attempt_lines(run["attempts"]),
          "The payload, output and metadata are left out, since they can hold customer data. Open the run in Trigger.dev to see them.",
          log_block(events, run["id"])
        ]
        Telemetry.result(lines.compact.join("\n"), link: run_link(environment_row, run["id"]))
      end

      def search_task_logs(environment_row:, arguments:)
        task = task_of(arguments)
        started, ended = Capabilities::Answers.range(arguments)
        line_limit = Capabilities::Answers.limit(arguments, LOG_LIMIT)
        matcher = matcher_for(arguments)
        runs = api(environment_row).runs(filter: run_filter(arguments.merge("task" => task), started, ended), limit: LOG_RUNS)
        lines = runs.first(LOG_RUNS).flat_map do |run|
          api(environment_row).run_events(run["id"]).filter_map do |event|
            line = log_line(event, run["id"])
            line if line && matcher.call(line.text)
          end
        end.sort_by(&:at).reverse.first(line_limit)
        asked = "the latest #{[ runs.size, LOG_RUNS ].min} runs of #{task} from #{started.utc.iso8601} to #{ended.utc.iso8601}"
        Telemetry.result(Telemetry.logs_text(lines, asked: asked, limit: line_limit),
                         link: (run_link(environment_row, lines.first&.source || runs.first["id"]) if runs.any?))
      end

      def describe_task(environment_row:, arguments:)
        task = task_of(arguments)
        deployment = deployed_version(environment_row)
        defined = Array(deployment&.dig("worker", "tasks")).find { |each| each["slug"] == task }
        queues = api(environment_row).queues
        queue = queues.items.find { |each| each["name"] == task && each["type"] == TASK_QUEUE }
        recent = api(environment_row).runs(filter: { "taskIdentifier" => [ task ], "createdAt" => { "period" => "1h" } }, limit: TriggerDevApi::PAGE_SIZE)
        outcomes = recent.group_by { |run| run["status"] }.transform_values(&:size).sort_by { |_, count| -count }.map { |status, count| "#{count} #{status}" }
        lines = [
          "Task #{task}",
          if deployment.nil? then no_deployment
          elsif defined then "Deployed in version #{deployment['version']}, defined in #{defined['filePath']} as #{defined['exportName']}"
          else "Not in version #{deployment['version']}, the newest deployed. Runs of a task the deployed version lacks wait in Pending version."
          end,
          queue ? queue_line(queue) : "Queue: not found among #{queues.incomplete? ? "the first #{queues.items.size} of " : ''}the environment's queues",
          "Runs in the last hour: #{outcomes.any? ? outcomes.join(', ') : 'none'}#{" (the first #{recent.size} read)" if recent.size >= TriggerDevApi::PAGE_SIZE}",
          no_page
        ]
        Telemetry.result(lines.join("\n"), link: nil)
      end

      def list_deployments(environment_row:, arguments:)
        status = arguments["status"].presence_in(DEPLOYMENT_STATUSES)
        deployments = api(environment_row).deployments(status: status, limit: Capabilities::Answers.limit(arguments, DEPLOYMENT_LIMIT))
        return Telemetry.result("This environment has no deployments#{" #{status}" if status}. #{no_page}", link: nil) if deployments.empty?

        rows = deployments.map { |deployment| deployment_line(deployment) }
        Telemetry.result("Latest #{rows.size} deployments, newest first. A version applies to every task in the environment, and " \
                         "promote_deployment takes one that deployed.\n#{rows.join("\n")}\n#{no_page}", link: nil)
      end

      def list_errors(environment_row:, arguments:)
        started, ended = Capabilities::Answers.range(arguments)
        filter = {
          "taskIdentifier" => ([ arguments["task"].to_s.strip ] if arguments["task"].present?), "search" => arguments["text"].presence,
          "status" => (Array(arguments["status"]) & ERROR_STATUSES).presence, "from" => started.utc.iso8601, "to" => ended.utc.iso8601
        }
        groups = api(environment_row).errors(filter: filter, limit: Capabilities::Answers.limit(arguments, ERROR_LIMIT)).sort_by { |group| -group["count"].to_i }
        asked = "from #{started.utc.iso8601} to #{ended.utc.iso8601}"
        return Telemetry.result("No errors #{asked}#{" in #{arguments['task']}" if arguments['task'].present?}. #{no_page}", link: nil) if groups.empty?

        rows = groups.map do |group|
          "#{group['count']} times: #{group['errorType']}: #{Chat::SecretFree.redacted(group['errorMessage']).truncate(300)}, task #{group['taskIdentifier']}, " \
            "#{group['status']}, first seen #{group['firstSeen']}, last seen #{group['lastSeen']}, id #{group['id']}"
        end
        Telemetry.result("#{rows.size} error groups #{asked}, most frequent first.\n#{rows.join("\n")}\n#{no_page}", link: nil)
      end

      def list_queues(environment_row:, arguments:)
        queue_read = api(environment_row).queues
        limit_read = api(environment_row).concurrency_limits
        queues = queue_read.items.sort_by { |queue| -queue["queued"].to_i }
        limits = limit_read.items.sort_by { |each| -each["queued"].to_i }
        lines = [ "#{queues.size} queues, most waiting first.#{cut(queue_read, 'queues')}", *queues.map { |queue| queue_line(queue) } ]
        if limits.any?
          lines << "#{limits.size} concurrency limits, most waiting first.#{cut(limit_read, 'concurrency limits')}"
          lines.concat(limits.map { |each| limit_line(each) })
        end
        Telemetry.result("#{lines.join("\n")}\n#{no_page}", link: nil)
      end

      def task_metrics(environment_row:, arguments:)
        task = task_of(arguments)
        started, ended = Capabilities::Answers.range(arguments)
        asked = Array(arguments["metrics"]).map(&:to_s) & METRICS
        asked = DEFAULT_METRICS if asked.empty?
        api = api(environment_row)
        counted = (asked & COUNTED).any? ? counts(api, task, started, ended) : {}
        charts = asked.map do |metric|
          points = COUNTED.include?(metric) ? counted.fetch(metric, []) : runtime(api, task, metric, started, ended)
          unit = COUNTED.include?(metric) ? COUNT : METRIC_UNITS.fetch(metric)
          Telemetry::Chart.new(title: "#{METRIC_TITLES.fetch(metric)} of #{task}", unit: unit,
                               series: [ Telemetry::Series.new(label: task, points: points) ], from: started, to: ended)
        end
        step = step_of(counted.values.flatten(1).map(&:first))
        every = step ? " Runs are counted per #{(step / 60.0).round(1)} minutes, the step Trigger.dev chose for the range." : ""
        Telemetry.result("#{task}\n#{Telemetry.charts_text(charts)}#{every}\n#{no_page}", charts: charts, link: nil)
      end

      # Only a version that deployed can be promoted, and only one in this environment, since the key reaches no other.
      def promote_deployment(environment_row:, arguments:)
        version = arguments["version"].to_s.strip
        fail! "Say which version to promote, such as 20250228.1. list_deployments shows them." unless version.match?(VERSION)

        api(environment_row).promote(version)
        Telemetry.result("Version #{version} is now the current version of this environment, for every task in it. New runs start on " \
                         "it. Runs already started, and their retries, keep the version they started on. #{no_page}", link: nil)
      rescue TriggerDevApi::Error => error
        raise if error.is_a?(Integrations::RateLimited) || !error.message.start_with?("Trigger.dev answered 401", "Trigger.dev answered 403")

        fail!(Sentence.join("Trigger.dev refused the promotion", error,
                            after: "This environment's API key cannot promote a deployment. In Trigger.dev, create a key whose preset can " \
                                   "deploy, such as No restrictions, and reconnect with it"))
      end

      # The tasks of the newest version deployed to the environment, each a job on the map. Trigger.dev documents no page
      # for a task, so they carry none.
      def map_of(environment_row)
        project = project_of(environment_row)
        deployment = deployed_version(environment_row)
        # Nothing deployed means no tasks, so the gap holds nothing back.
        return ResourceMap::Snapshot.new(resources: [], links: [], gaps: [ ResourceMap::Gap.new(text: no_deployment, kinds: []) ]) unless deployment

        resources = Array(deployment.dig("worker", "tasks")).filter_map do |task|
          next if task["slug"].blank?

          ResourceMap::Found.new(provider: PROVIDER_KEY, account: project, kind: ResourceMap::KIND_JOB, external_id: task["slug"],
                                 name: task["slug"], status: deployment["status"].to_s.downcase.presence, url: nil,
                                 details: { "version" => deployment["version"], "file" => task["filePath"] }.compact)
        end
        uses, gaps = settings_of(environment_row, project, resources)
        ResourceMap::Snapshot.new(resources: resources, links: [], gaps: gaps, uses: uses)
      end

      # What normal looks like for each task over the week: runs started and failed per minute, and the CPU and memory of
      # its runs, each from one query over every task. A bucket with no runs is a zero, so a quiet task's normal is not
      # read off its busy minutes only. Being asked to slow down stops the whole read.
      def baselines_of(environment_row, resources, window)
        tasks = resources.select { |resource| resource.kind == ResourceMap::KIND_JOB }.index_by(&:external_id)
        return [] if tasks.empty?

        api = api(environment_row)
        rows = grouped_rows(api, tasks.keys, window) { |task| grouped_counts(task) }
        step = step_of(rows.filter_map { |row| Telemetry.parse_time(row["bucket"]) })
        found = step ? counted_baselines(tasks, rows, step, window) : []
        found + RUNTIME_METRICS.keys.flat_map do |metric|
          grouped_rows(api, tasks.keys, window) { |task| grouped_runtime(metric, task) }.group_by { |row| row["task"] }.filter_map do |task, readings|
            resource = tasks[task]
            next unless resource

            points = readings.filter_map { |row| (at = Telemetry.parse_time(row["bucket"])) && [ at, scale(metric, row["value"]) ] }
            ResourceMap::Baseline::Found.new(key: resource.key, metric: metric, label: METRIC_TITLES.fetch(metric), unit: METRIC_UNITS.fetch(metric), points: points)
          end
        end
      end

      # A GET the read guard let through (ReadGuards::TriggerDev). The key reaches one project environment, which is all
      # the connection reads, so nothing else keeps it in. A run's page is the one address Trigger.dev documents, so an
      # answer that is one run links it.
      def api_read(environment_row:, arguments:)
        call = begin
          ReadGuards::TriggerDev.reading(ApiReads::TOOL, arguments)
        rescue ReadGuards::Refused => error
          fail!(error.message)
        end
        path, query = call.values_at("path", "query")
        fail!("path starts with /api, as the API reference writes it, such as /api/v1/schedules.") unless path.start_with?("/api/")

        answer = api(environment_row).read(path, query.transform_values { |value| Array(value).join(",") })
        run = path.match(%r{/runs/(run_[A-Za-z0-9]+)})&.[](1)
        text = ApiReads.answer(PROVIDER, ApiReads.asked(path, query), answer, secret: ReadGuards::TriggerDev.secret?(path))
        Telemetry.result(text, link: run_link(environment_row, run))
      end

      def check_health!(environment_row)
        project_of(environment_row)
        api(environment_row).runs(limit: TriggerDevApi::MIN_RUN_PAGE)
      rescue TriggerDevApi::Error => error
        fail! error.message
      end

      private

      def api(environment_row)
        key = ConnectionSettings.of(environment_row).credential(API_KEY)
        fail! "This environment has no Trigger.dev API key. Reconnect it on the Integrations page." if key.blank?

        TriggerDevApi.new(key)
      end

      # The environment's variables, which every task in it runs with, read in memory with one call. A secret's value comes
      # back redacted, so it is known by its name. A key whose preset cannot read variables, such as Observer, is refused,
      # which is a gap that keeps what was read before.
      def settings_of(environment_row, project, tasks)
        return [ [], [] ] if tasks.empty?

        slug = ConnectionSettings.of(environment_row).credential(API_KEY).to_s[KEY_ENVIRONMENT, 1]
        variables = api(environment_row).environment_variables(project, slug)
        secret, plain = variables.partition { |variable| variable["isSecret"] }
        values = plain.to_h { |variable| [ variable["name"].to_s, variable["value"].to_s ] }
        names = secret.map { |variable| variable["name"].to_s }
        workspace = ConnectionSettings.of(environment_row).workspace
        [ tasks.flat_map { |task| ResourceMap::Use.read(from: task.key, workspace: workspace, values: values, names: names) }, [] ]
      rescue Integrations::RateLimited
        [ [], [ ResourceMap::Gap.new(text: "Trigger.dev asked Firefight to slow down, so the environment's variables are read at the next sweep.",
                                     kinds: [], settings: true) ] ]
      rescue TriggerDevApi::Error => error
        [ [], [ ResourceMap::Gap.new(text: Sentence.join("Trigger.dev refused the environment's variables", error,
                                                         after: "So the tasks are not linked to what their variables name. This is optional. " \
                                                                "Observer keeps the connection read only and cannot read environment variables, " \
                                                                "and a key whose preset can read them links the tasks too"),
                                     kinds: [], settings: true) ] ]
      end

      def project_of(environment_row) = ConnectionSettings.of(environment_row).field(PROJECT) || fail!("This environment has no Trigger.dev project ref. Reconnect it.")

      def task_of(arguments)
        task = arguments["task"].to_s.strip
        fail! "Say which task, by its identifier. list_tasks shows them." if task.empty?
        fail! "#{task} is not a task identifier. list_tasks shows them." unless task.match?(TASK_ID)

        task
      end

      # The newest deployment that deployed, with its tasks. Trigger.dev lists deployments without saying which is current,
      # so a version promoted back over a newer one is not told apart here.
      def deployed_version(environment_row)
        latest = api(environment_row).deployments(status: DEPLOYED, limit: TriggerDevApi::MIN_DEPLOYMENT_PAGE).first
        latest && api(environment_row).deployment(latest["id"])
      end

      def no_deployment = "Nothing is deployed to this environment, so it has no tasks to read."

      # Said after a list cut short at its page bound, so it is never taken for the whole.
      def cut(read, what) = read.incomplete? ? " Only the first #{read.items.size} #{what} were read." : ""

      def no_page = "Trigger.dev documents no page address for this, so there is no link to give."

      def run_filter(arguments, started, ended)
        {
          "taskIdentifier" => ([ arguments["task"].to_s.strip ] if arguments["task"].present?),
          "status" => (Array(arguments["status"]) & RUN_STATUSES).presence,
          "createdAt" => { "from" => started.utc.iso8601, "to" => ended.utc.iso8601 }
        }
      end

      # A run's page on the registry's site, as Trigger.dev's own MCP server writes it (packages/cli-v3/src/mcp/tools/runs.ts).
      # Trigger.dev documents no address for a task, a deployment or an error group.
      def run_link(environment_row, run_id)
        return nil if run_id.blank?

        Telemetry::Link.new(provider: PROVIDER, url: "#{ConnectionSettings.of(environment_row).site.to_s.chomp('/')}/projects/v3/#{Http.segment(project_of(environment_row))}/runs/#{Http.segment(run_id)}")
      end

      def run_line(environment_row, run)
        [ run["createdAt"], run["id"], run["taskIdentifier"], run["status"], ("version #{run['version']}" if run["version"]),
          ("started #{run['startedAt']}" if run["startedAt"]), ("finished #{run['finishedAt']}" if run["finishedAt"]),
          ("computed #{run['durationMs']} ms" if run["durationMs"]), run_link(environment_row, run["id"])&.url ].compact.join(", ")
      end

      # A run in the words every run history uses, its status read from the runs API's own (CommonRunsFilter).
      def history_run(environment_row, run)
        Capabilities::History::Run.new(
          id: run["id"], name: run["taskIdentifier"], status: Capabilities::History.status(run["status"], HISTORY_STATUSES),
          started_at: Capabilities::RunHistory.time(run["startedAt"] || run["createdAt"]), finished_at: Capabilities::RunHistory.time(run["finishedAt"]),
          url: run_link(environment_row, run["id"])&.url, detail: ("version #{run['version']}" if run["version"])
        )
      end

      def related_line(related)
        return nil if related.blank?

        parts = [ ("parent #{related.dig('parent', 'id')} (#{related.dig('parent', 'status')})" if related["parent"]),
                  ("root #{related.dig('root', 'id')}" if related["root"]),
                  ("#{Array(related['children']).size} child runs, #{Array(related['children']).count { |child| FAILED_STATUSES.include?(child['status']) }} failed" if Array(related["children"]).any?) ].compact
        "Related: #{parts.join(', ')}" if parts.any?
      end

      def attempt_lines(attempts)
        return "Attempts: none yet" if Array(attempts).empty?

        rows = attempts.map.with_index(1) do |attempt, number|
          error = attempt["error"]
          said = error ? ", #{error['name'] || 'Error'}: #{Chat::SecretFree.redacted(error['message']).truncate(MESSAGE_LIMIT)}" : ""
          stack = error && error["stackTrace"].present? ? "\n#{error['stackTrace'].lines.first(STACK_LINES).join.rstrip}" : ""
          "Attempt #{number}, #{attempt['status']}, started #{attempt['startedAt'] || 'not yet'}, completed #{attempt['completedAt'] || 'not yet'}#{said}#{stack}"
        end
        "Attempts:\n#{rows.join("\n")}"
      end

      def log_block(events, run_id)
        lines = events.filter_map { |event| log_line(event, run_id) }.sort_by(&:at).reverse
        Telemetry.logs_text(lines.first(LOG_LIMIT), asked: "run #{run_id}", limit: LOG_LIMIT)
      end

      # One event of a run as a log line, its time read from nanoseconds since the epoch (get_run_events_v1).
      def log_line(event, run_id)
        text = event["message"].to_s
        return nil if text.blank?

        at = Time.zone.at(event["startTime"].to_i / NANOSECONDS).utc if event["startTime"].present?
        level = event["level"].presence
        failed = event["isError"] ? " (error)" : ""
        Telemetry::LogLine.new(at: at || Time.current, source: run_id, text: "#{"#{level} " if level}#{text}#{failed}")
      end

      def matcher_for(arguments)
        text = arguments["text"].presence
        exclude = arguments["exclude"].presence
        pattern = begin
          Regexp.new(arguments["regex"], timeout: 1) if arguments["regex"].present?
        rescue RegexpError => error
          fail!(Sentence.join("regex is not a regular expression", error))
        end
        lambda do |line|
          (!text || line.include?(text)) && (!exclude || line.exclude?(exclude)) && (!pattern || pattern.match?(line))
        rescue Regexp::TimeoutError
          fail!("The regular expression took too long on Trigger.dev's lines. Make it simpler, or search by text instead.")
        end
      end

      def deployment_line(deployment)
        error = deployment["error"].presence
        [ deployment["createdAt"], "version #{deployment['version']}", deployment["status"],
          ("deployed #{deployment['deployedAt']}" if deployment["deployedAt"]), ("id #{deployment['id']}" if deployment["id"]),
          ("git #{Chat::SecretFree.redacted(deployment['git'].to_json).truncate(300)}" if deployment["git"].present?),
          ("error #{Chat::SecretFree.redacted(error.to_json).truncate(500)}" if error) ].compact.join(", ")
      end

      def queue_line(queue)
        limit = queue["concurrencyLimit"] || queue.dig("concurrency", "current")
        [ "Queue #{queue['name']} (#{queue['type']})", "#{queue['running']} executing", "#{queue['queued']} waiting",
          ("paused" if queue["paused"]), "limit #{limit || 'none of its own'}" ].compact.join(", ")
      end

      def limit_line(each)
        [ "Limit #{each['name']}", "#{each['running']} executing", "#{each['queued']} waiting", ("paused" if each["paused"]),
          "total #{each.dig('total', 'current') || 'unbounded'}", "per key #{each.dig('perKey', 'current') || 'unbounded'}" ].compact.join(", ")
      end

      def quoted(task) = "'#{task}'"

      # Runs started and failed per time step, as TRQL counts them (timeBucket picks the step for the range).
      def counts(api, task, started, ended)
        rows = api.query("SELECT timeBucket() AS bucket, count() AS runs, countIf(status IN ('Failed', 'Crashed')) AS failed FROM runs " \
                         "WHERE task_identifier = #{quoted(task)} GROUP BY bucket ORDER BY bucket LIMIT #{QUERY_ROWS}", from: started, to: ended)
        points = rows.filter_map { |row| (at = Telemetry.parse_time(row["bucket"])) && [ at, row["runs"].to_f, row["failed"].to_f ] }
        step = step_of(points.map(&:first))
        points = filled(points.to_h { |at, runs, failed| [ at, [ runs, failed ] ] }, step, started, ended) if step
        { "requests" => points.map { |at, runs, _| [ at, runs ] }, "errors" => points.map { |at, _, failed| [ at, failed ] } }
      end

      def runtime(api, task, metric, started, ended)
        rows = api.query("SELECT timeBucket() AS bucket, avg(metric_value) AS value FROM metrics WHERE task_identifier = #{quoted(task)} " \
                         "AND metric_name = '#{RUNTIME_METRICS.fetch(metric)}' GROUP BY bucket ORDER BY bucket LIMIT #{QUERY_ROWS}", from: started, to: ended)
        rows.filter_map { |row| (at = Telemetry.parse_time(row["bucket"])) && [ at, scale(metric, row["value"]) ] }
      end

      # The rows of one query over every task, or of one query per task when that one filled QUERY_ROWS, since its rows
      # come oldest bucket first and the newest would be the ones cut.
      def grouped_rows(api, tasks, window)
        rows = api.query(yield(nil), from: window.begin, to: window.end)
        return rows if rows.size < QUERY_ROWS

        tasks.select { |task| task.match?(TASK_ID) }.flat_map { |task| api.query(yield(task), from: window.begin, to: window.end) }
      end

      def grouped_counts(task = nil)
        "SELECT task_identifier AS task, timeBucket() AS bucket, count() AS runs, countIf(status IN ('Failed', 'Crashed')) AS failed " \
          "FROM runs #{"WHERE task_identifier = #{quoted(task)} " if task}GROUP BY task, bucket ORDER BY bucket LIMIT #{QUERY_ROWS}"
      end

      def grouped_runtime(metric, task = nil)
        "SELECT task_identifier AS task, timeBucket() AS bucket, avg(metric_value) AS value FROM metrics " \
          "WHERE metric_name = '#{RUNTIME_METRICS.fetch(metric)}' #{"AND task_identifier = #{quoted(task)} " if task}GROUP BY task, bucket " \
          "ORDER BY bucket LIMIT #{QUERY_ROWS}"
      end

      def counted_baselines(tasks, rows, step, window)
        per_minute = 60.0 / step
        rows.group_by { |row| row["task"] }.flat_map do |task, readings|
          resource = tasks[task]
          next [] unless resource

          by_bucket = readings.filter_map { |row| (at = Telemetry.parse_time(row["bucket"])) && [ at, [ row["runs"].to_f, row["failed"].to_f ] ] }.to_h
          points = filled(by_bucket, step, window.begin, window.end)
          [ [ "requests", 1 ], [ "errors", 2 ] ].map do |metric, index|
            ResourceMap::Baseline::Found.new(key: resource.key, metric: metric, label: METRIC_TITLES.fetch(metric), unit: PER_MINUTE,
                                             points: points.map { |point| [ point.first, point[index] * per_minute ] })
          end
        end
      end

      # Every step from the start of the range to its end, with zero runs where Trigger.dev returned no row. Buckets are
      # matched by their second, so a step worked out in floating point still lands on Trigger.dev's own.
      def filled(by_bucket, step, started, ended)
        seconds = by_bucket.transform_keys(&:to_i)
        origin = seconds.keys.min || started.to_i
        first = origin - (((origin - started.to_i) / step).floor * step)
        (0..((ended.to_i - first) / step).floor).map do |index|
          at = (first + (index * step)).round
          [ Time.zone.at(at).utc, *seconds.fetch(at) { [ 0.0, 0.0 ] } ]
        end
      end

      # The step Trigger.dev chose for the range, as the smallest gap between two buckets.
      def step_of(times)
        times.map(&:to_i).uniq.sort.each_cons(2).map { |first, second| second - first }.select(&:positive?).min
      end

      def scale(metric, value)
        return value.to_f * 100 if metric == "cpu"

        value.to_f / 1_048_576
      end
    end
  end
end
