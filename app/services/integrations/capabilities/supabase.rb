module Integrations
  module Capabilities
    # Supabase answers through the tools its MCP server publishes, from supabase-community/supabase-mcp,
    # packages/mcp-server-supabase/src/tools. A project is a database on the map and each branch is a project of its own,
    # so both are asked by their project ref. Logs come from query_logs, which runs SQL over Supabase's unified log stream
    # and which the hosted server offers in place of get_logs. Firefight writes that SQL with the columns get_logs reads
    # in src/logs.ts, every value a quoted literal. Deploys are the migrations applied, and status is the project as
    # Supabase's API answers it. A connection scoped to one project by its project_ref connect field takes no project_id,
    # so project_id goes only to a tool that asks for it.
    #
    # An Edge Function is a function on the map, ref/slug, read through list_edge_functions (edge-function-tools.ts), which
    # gives its status, the version it runs and when that was deployed. Supabase keeps only the version a function runs,
    # so its deploys are that one. Its logs are what it prints (function_logs) and its invocations (function_edge_logs),
    # read by the function_id get_logs reads them with. A preview branch rolls back to an earlier migration with
    # reset_branch (branching-tools.ts), which takes the branch's own id and a migration version.
    #
    # What the server has no tool for is the pack's beside it (Packs::Supabase), through the Management API: a project's or
    # branch's action runs as its run history, its status with each service's health, its metrics now, restarting it,
    # and rolling the project's database back to a moment with point in time recovery. Its errors are the performance
    # warnings get_advisors gives (debugging-tools.ts), and its auth, storage and realtime logs are read as get_logs reads
    # them (src/logs.ts).
    module Supabase
      extend Adapter

      PROVIDER = MapReaders::Supabase::NAME
      PROVIDER_KEY = MapReaders::Supabase::PROVIDER
      PROJECTS = [ ResourceMap::KIND_DATABASE, ResourceMap::KIND_BRANCH ].freeze
      READ_KINDS = [ *PROJECTS, ResourceMap::KIND_FUNCTION ].freeze
      SUPPORTS = {
        LOGS => READ_KINDS, DEPLOYS => READ_KINDS, STATUS => READ_KINDS, ROLLBACK => PROJECTS, HISTORY => PROJECTS, RESTART => PROJECTS,
        METRICS => PROJECTS, ERRORS => PROJECTS
      }.freeze
      GET_PROJECT = "get_project".freeze
      PROJECT_HEALTH = "get_project_health".freeze
      LIST_ACTION_RUNS = "list_action_runs".freeze
      GET_ACTION_RUN = "get_action_run".freeze
      RESTART_PROJECT = "restart_project".freeze
      PROJECT_METRICS = "get_project_metrics".freeze
      RESTORE_TO = "restore_to_point_in_time".freeze
      GET_ADVISORS = "get_advisors".freeze
      # get_advisors' kind of warning that says what slows a project down, beside its security ones.
      PERFORMANCE = "performance".freeze
      LIST_MIGRATIONS = "list_migrations".freeze
      LIST_EDGE_FUNCTIONS = MapReaders::Supabase::LIST_EDGE_FUNCTIONS
      RESET_BRANCH = "reset_branch".freeze
      # An Edge Function serving requests, as edgeFunctionSchema names its status.
      FUNCTION_ACTIVE = "ACTIVE".freeze
      TOOLS = {
        LOGS => "query_logs", DEPLOYS => [ LIST_MIGRATIONS, LIST_EDGE_FUNCTIONS ], STATUS => [ PROJECT_HEALTH, GET_PROJECT, LIST_EDGE_FUNCTIONS ],
        ROLLBACK => [ RESET_BRANCH, RESTORE_TO ], HISTORY => [ LIST_ACTION_RUNS, GET_ACTION_RUN ], RESTART => RESTART_PROJECT,
        METRICS => PROJECT_METRICS, ERRORS => GET_ADVISORS
      }.freeze
      # The readings get_project_metrics takes, by the capability's metric names.
      METRIC_MAP = { "cpu" => "cpu", "memory" => "memory", "disk" => "disk" }.freeze
      # An Edge Function's logs, by stream, as get_logs reads its edge-function-runtime and edge-function services.
      FUNCTION_SOURCES = { STREAM_APP => "function_logs", "requests" => "function_edge_logs" }.freeze
      FUNCTION_COLUMNS = {
        "function_logs" => "timestamp, event_message, severity_text as level, log_attributes['version'] as version",
        "function_edge_logs" => "timestamp, event_message, log_attributes['request.method'] as method, log_attributes['response.status_code'] as status_code, " \
                                "log_attributes['execution_time_ms'] as execution_time_ms, log_attributes['version'] as version"
      }.freeze
      FUNCTION_READS = { "function_logs" => "what Edge Function", "function_edge_logs" => "invocations of Edge Function" }.freeze
      # Supabase's tools reach every project the account sees, far beyond the map, so they stay offered as they are.
      WRAPPED = [].freeze
      PROJECT_ID = "project_id".freeze
      SCOPED_TO = "project_ref".freeze
      # The log sources a stream reads, and the columns each is read with, as the server's get_logs reads them.
      # A branch's build is its branch action, the run that migrates and seeds it, logged as workflow_run_logs (get_logs'
      # branch-action service).
      BRANCH_ACTIONS = "workflow_run_logs".freeze
      SOURCES = {
        STREAM_APP => "postgres_logs", "requests" => "edge_logs", STREAM_BUILD => BRANCH_ACTIONS, STREAM_AUTH => "auth_logs",
        STREAM_STORAGE => "storage_logs", STREAM_REALTIME => "realtime_logs"
      }.freeze
      COLUMNS = {
        "postgres_logs" => "timestamp, event_message, log_attributes['parsed.error_severity'] as error_severity",
        "edge_logs" => "timestamp, event_message, log_attributes['request.method'] as method, log_attributes['request.path'] as path, " \
                       "log_attributes['response.status_code'] as status_code",
        BRANCH_ACTIONS => "timestamp, event_message, log_attributes['workflow_run'] as workflow_run",
        "auth_logs" => "timestamp, event_message, log_attributes['level'] as level, log_attributes['status'] as status_code, log_attributes['path'] as path, " \
                       "log_attributes['msg'] as msg, log_attributes['error'] as error",
        "storage_logs" => "timestamp, event_message",
        "realtime_logs" => "timestamp, event_message"
      }.freeze
      # The Logs page guides/telemetry/logs opens, which takes every log type, for the ones without a page of their own.
      PAGES = {
        "postgres_logs" => "logs/postgres-logs", "edge_logs" => "logs/edge-logs", BRANCH_ACTIONS => "logs/explorer", "auth_logs" => "logs",
        "storage_logs" => "logs", "realtime_logs" => "logs"
      }.freeze
      READS = {
        "postgres_logs" => "Postgres logs of", "edge_logs" => "API requests to", BRANCH_ACTIONS => "Branch action runs of", "auth_logs" => "Auth logs of",
        "storage_logs" => "Storage logs of", "realtime_logs" => "Realtime logs of"
      }.freeze
      MIGRATIONS_PAGE = "database/migrations".freeze
      LOG_LIMIT = 200
      LOG_MOST = 1_000
      # The server refuses a log window longer than a day.
      WINDOW_MINUTES = 24 * 60
      DEPLOY_LIMIT = 20
      DEPLOY_MOST = 100
      # What the server wraps every log answer in, so the rows can be read back out of it.
      UNTRUSTED = /<untrusted-data-[^>]+>\s*(?<data>.*?)\s*<\/untrusted-data-[^>]+>/m
      MIGRATION_TIME = /\A\d{14}\z/

      def self.route(key, resource, given, tool:, settings: nil)
        ref = ref_of(resource)
        scoped!(resource, settings)
        return function_route(key, resource, ref, given, settings) if resource.kind == ResourceMap::KIND_FUNCTION

        case key
        when LOGS then logs(resource, ref, given, tool)
        when DEPLOYS
          Route.new(tool_name: LIST_MIGRATIONS, arguments: project(ref, tool),
                    present: ->(result) { Answers.read(result, PROVIDER) { |data| deploys_result(resource, data, given) } })
        when STATUS
          return Route.new(tool_name: PROJECT_HEALTH, arguments: pack_project(ref, settings)) if tool&.name == PROJECT_HEALTH

          Route.new(tool_name: GET_PROJECT, arguments: { "id" => ref },
                    present: ->(result) { Answers.read(result, PROVIDER) { |data| status_result(resource, data) } })
        when ROLLBACK then resource.kind == ResourceMap::KIND_DATABASE ? restore(resource, ref, given, settings) : rollback(resource, given)
        when HISTORY then history(resource, ref, given, settings)
        when RESTART then Route.new(tool_name: RESTART_PROJECT, arguments: pack_project(ref, settings))
        when METRICS
          readings = metric_names(given.merge("metrics" => Array(given["metrics"]).presence || METRIC_MAP.keys), METRIC_MAP, PROVIDER)
          Route.new(tool_name: PROJECT_METRICS, arguments: pack_project(ref, settings).merge("readings" => readings))
        when ERRORS then advisors(resource, ref, given, tool)
        end
      end

      # The pack's tools take the project as project_id, which a connection scoped to it may leave out.
      def self.pack_project(ref, settings) = settings&.field(SCOPED_TO).present? ? {} : { PROJECT_ID => ref }

      # A branch's action runs, or one of them by its id with its steps.
      def self.history(resource, ref, given, settings)
        arguments = pack_project(ref, settings)
        return Route.new(tool_name: GET_ACTION_RUN, arguments: arguments.merge("run_id" => given["run"].to_s.strip)) if given["run"].present?

        Route.new(tool_name: LIST_ACTION_RUNS, arguments: arguments.merge("limit" => given["limit"]).compact_blank,
                  present: RunHistory.presenter("the action runs of #{resource.name}", given))
      end

      # The project's database back to a moment, as an ISO 8601 time, with point in time recovery. A preview branch rolls
      # back with reset_branch instead.
      def self.restore(resource, ref, given, settings)
        at = Packs::Supabase.moment(target(given))
        unless at
          raise Unroutable, "Supabase restores #{resource.name} to a moment, so say it as an ISO 8601 time, as list_backups shows the range. " \
                            "A migration's version is not a moment, and only a preview branch goes back to a migration."
        end

        Route.new(tool_name: RESTORE_TO, arguments: pack_project(ref, settings).merge("to" => at.utc.iso8601),
                  keeps: "nothing after #{at.utc.iso8601}, which is lost")
      end

      # The performance warnings get_advisors gives for a project, such as a missing index, which are what Supabase says is
      # wrong with it. They are setup checks rather than errors the database raised, and the answer says so. The security
      # ones are read with get_advisors itself.
      def self.advisors(resource, ref, given, tool)
        Route.new(tool_name: GET_ADVISORS, arguments: project(ref, tool).merge("type" => PERFORMANCE),
                  present: ->(result) { Answers.read(result, PROVIDER) { |data| advisors_result(result, resource, data, given) } })
      end

      def self.advisors_result(result, resource, data, given)
        found = data.is_a?(Hash) ? (data.dig("result", "lints") || data["lints"]) : nil
        return nil unless found.is_a?(Array)

        lints = found.select { |lint| lint.is_a?(Hash) }
        lints = lints.select { |lint| lint.to_json.downcase.include?(given["text"].to_s.downcase) } if given["text"].present?
        return Answers.presented(result, "Supabase gives no performance warnings for #{resource.name}.") if lints.empty?

        lines = lints.first(Answers.limit(given, 50)).map do |lint|
          detail = Array(lint["findings"]).filter_map { |finding| finding["detail"] if finding.is_a?(Hash) }.first || lint["detail"]
          count = lint["count"].to_i > 1 ? " (#{lint['count']} findings)" : ""
          "- #{lint['level']}: #{lint['title']}#{count}. #{detail.to_s.squish.truncate(300)}#{" #{lint['remediation']}" if lint['remediation'].present?}"
        end
        Answers.presented(result, "Supabase's performance warnings for #{resource.name}, from its advisors. They are checks on how the project is " \
                                  "set up, not errors the database raised, which search_logs reads.\n#{lines.join("\n")}")
      end

      # A function is ref/slug on the map, and everything else its own project ref.
      def self.ref_of(resource) = resource.external_id.to_s.split("/", 2).first

      # A function's status and deploys both read what list_edge_functions says of it, and its logs are its own log sources.
      def self.function_route(key, resource, ref, given, settings)
        slug = resource.external_id.to_s.split("/", 2).last
        # The server fills the project in on a connection scoped to one, and takes it from the call otherwise.
        arguments = settings&.field(SCOPED_TO).present? ? {} : { PROJECT_ID => ref }
        case key
        when LOGS then function_logs(resource, arguments, given)
        when DEPLOYS, STATUS
          Route.new(tool_name: LIST_EDGE_FUNCTIONS, arguments: arguments,
                    present: ->(result) { Answers.read(result, PROVIDER) { |data| function_result(resource, slug, data, key) } })
        end
      end

      # Back to an earlier migration, by the version recent_deploys gives, on a preview branch. The project's own branch is
      # production, which reset_branch does not take, and a branch the map read before it kept branch ids is named again
      # at the next sweep.
      def self.rollback(resource, given)
        version = target(given)
        details = resource.details.to_h
        if details[ResourceMap::PRODUCTION]
          raise Unroutable, "#{resource.name} is the project's production branch, and Supabase resets only preview branches. Going back there is a new migration the person writes."
        end

        branch = details[MapReaders::Supabase::BRANCH_ID].presence
        raise Unroutable, "Firefight has not read the branch id of #{resource.name} yet, which reset_branch needs. It is read at the next map sweep." unless branch

        Route.new(tool_name: RESET_BRANCH, arguments: { "branch_id" => branch, "migration_version" => version },
                  present: lambda { |result|
                    Answers.read(result, PROVIDER) do |_data|
                      Telemetry.result("Supabase is resetting #{resource.name} to migration #{version}. Changes to its data or schema that " \
                                       "no migration made are lost. Its status in list_branches says when it is done.",
                                       link: Answers.page(resource, PROVIDER))
                    end
                  })
      end

      def self.function_logs(resource, arguments, given)
        source = FUNCTION_SOURCES[given["stream"].presence || STREAM_APP]
        raise Unroutable, "Supabase reads what an Edge Function prints with stream app and its invocations with stream requests." unless source

        id = resource.details.to_h[MapReaders::Supabase::FUNCTION_ID].presence
        raise Unroutable, "Firefight has not read the id of #{resource.name} yet, which its log lines carry. It is read at the next map sweep." unless id

        limit = Answers.limit(given, LOG_MOST, default: LOG_LIMIT)
        started, ended = window(given)
        filters = [ "source = #{literal(source)}", "log_attributes['function_id'] = #{literal(id)}" ]
        filters << "positionCaseInsensitive(event_message, #{literal(given['text'])}) > 0" if given["text"].present?
        filters << "positionCaseInsensitive(event_message, #{literal(given['exclude'])}) = 0" if given["exclude"].present?
        filters << "match(event_message, #{literal(given['regex'])})" if given["regex"].present?
        sql = "select #{FUNCTION_COLUMNS.fetch(source)} from logs where #{filters.join(' and ')} order by timestamp desc limit #{limit}"
        Route.new(tool_name: TOOLS[LOGS], arguments: arguments.merge("sql" => sql, "iso_timestamp_start" => started.utc.iso8601, "iso_timestamp_end" => ended.utc.iso8601),
                  present: ->(result) { Answers.read(result, PROVIDER) { |data| function_logs_result(resource, source, data, limit) } })
      end

      def self.function_logs_result(resource, source, data, limit)
        wrapped = data.is_a?(Hash) ? data["result"] : data
        inner = wrapped.is_a?(String) && (match = wrapped.match(UNTRUSTED)) ? JSON.parse(match[:data]) : wrapped
        failure = inner.is_a?(Hash) ? inner["error"] : nil
        if failure.present?
          said = failure.is_a?(Hash) ? (failure["message"] || failure.to_json) : failure.to_s
          return { "isError" => true, "content" => [ { "type" => "text", "text" => Sentence.join("Supabase could not read the logs", said) } ] }
        end

        lines = Array(inner.is_a?(Hash) ? inner["result"] : inner).filter_map do |row|
          at = Answers.time_of(row["timestamp"])
          took = row["execution_time_ms"].presence && "#{row['execution_time_ms']}ms"
          version = row["version"].presence && "v#{row['version']}"
          text = [ version, row["level"], row["method"], row["status_code"], took, row["event_message"] ].compact_blank.join(" ")
          Telemetry::LogLine.new(at: at, source: resource.name, text: text) if at && text.present?
        end.sort_by(&:at).reverse
        Telemetry.result(Telemetry.logs_text(lines, asked: "#{FUNCTION_READS.fetch(source)} #{resource.name}#{' printed' if source == FUNCTION_SOURCES[STREAM_APP]}", limit: limit),
                         link: Answers.page(resource, PROVIDER))
      end

      # The one function in the project's list: how it stands, or the version it runs and when that was deployed.
      def self.function_result(resource, slug, data, key)
        function = Array(data.is_a?(Hash) ? data["functions"] : data).find { |each| each.is_a?(Hash) && each["slug"] == slug }
        link = Answers.page(resource, PROVIDER)
        return Telemetry.result("Supabase lists no Edge Function #{slug} in this project now, so it was removed or renamed.", link: link) unless function

        deployed = Answers.time_of(function["updated_at"])&.iso8601
        if key == DEPLOYS
          result = Telemetry.result("#{resource.name} runs version #{function['version']}#{", deployed #{deployed}" if deployed}. Supabase keeps only " \
                                    "the version a function runs, so earlier deploys are not listed.", link: link)
          return Deploys.with_deploys(result, [ function_deploy(function) ])
        end

        facts = [ ("status #{function['status']}" if function["status"]), ("version #{function['version']}" if function["version"]),
                  ("deployed #{deployed}" if deployed), (function["verify_jwt"] ? "requires a signed in user's JWT" : "open without a JWT" unless function["verify_jwt"].nil?) ]
        Telemetry.result("How #{resource.name} stands on Supabase now: #{facts.compact.join(', ')}.", link: link)
      end

      # The version a function runs is the one Supabase deployed last, so it rolled out, and it serves while the function is active.
      def self.function_deploy(function)
        Deploys::Deploy.new(version: function["version"], status: History::SUCCEEDED, live: (true if function["status"] == FUNCTION_ACTIVE),
                            finished_at: Answers.time_of(function["updated_at"]))
      end

      # A connection scoped to one project reads only that one, whatever is asked, so another project is refused.
      def self.scoped!(resource, settings)
        scoped = settings&.field(SCOPED_TO)
        return if scoped.blank? || scoped == ref_of(resource)

        raise Unroutable, "This Supabase connection is scoped to project #{scoped}, so it cannot read #{resource.name}. Connect Supabase for that project too."
      end

      # A page of the project under its dashboard address, which the map read.
      def self.page(resource, path) = resource.url.present? ? "#{resource.url}/#{path}" : nil

      def self.takes_project?(tool) = Answers.properties(tool).to_h.key?(PROJECT_ID)

      def self.project(ref, tool) = tool.nil? || takes_project?(tool) ? { PROJECT_ID => ref } : {}

      def self.logs(resource, ref, given, tool)
        source = SOURCES[given["stream"].presence || STREAM_APP]
        unless source
          raise Unroutable, "Supabase reads a project's Postgres logs with stream app, the API requests reaching it with stream requests, " \
                            "its branch action runs with stream build, and its auth, storage and realtime logs with those streams."
        end

        limit = Answers.limit(given, LOG_MOST, default: LOG_LIMIT)
        started, ended = window(given)
        filters = [ "source = #{literal(source)}" ]
        filters << "positionCaseInsensitive(event_message, #{literal(given['text'])}) > 0" if given["text"].present?
        filters << "positionCaseInsensitive(event_message, #{literal(given['exclude'])}) = 0" if given["exclude"].present?
        filters << "match(event_message, #{literal(given['regex'])})" if given["regex"].present?
        sql = "select #{COLUMNS.fetch(source)} from logs where #{filters.join(' and ')} order by timestamp desc limit #{limit}"
        arguments = project(ref, tool).merge("sql" => sql, "iso_timestamp_start" => started.utc.iso8601, "iso_timestamp_end" => ended.utc.iso8601)
        Route.new(tool_name: TOOLS[LOGS], arguments: arguments,
                  present: ->(result) { Answers.read(result, PROVIDER) { |data| logs_result(resource, source, data, limit) } })
      end

      # The window Supabase reads, which it caps at a day, so a longer one is said rather than cut short unseen.
      def self.window(given)
        started, ended = Answers.range(given)
        if ended - started > WINDOW_MINUTES.minutes
          raise Unroutable, "Supabase reads at most a day of logs a call. Ask for #{WINDOW_MINUTES} minutes or fewer, or a start and end within a day."
        end

        [ started, ended ]
      end

      # A ClickHouse string literal with its backslashes and quotes escaped, so what was asked is only ever read as text.
      def self.literal(value) = "'#{value.to_s.gsub('\\') { '\\\\' }.gsub("'") { "\\'" }}'"

      def self.logs_result(resource, source, data, limit)
        wrapped = data.is_a?(Hash) ? data["result"] : data
        inner = wrapped.is_a?(String) && (match = wrapped.match(UNTRUSTED)) ? JSON.parse(match[:data]) : wrapped
        failure = inner.is_a?(Hash) ? inner["error"] : nil
        if failure.present?
          said = failure.is_a?(Hash) ? (failure["message"] || failure.to_json) : failure.to_s
          return { "isError" => true, "content" => [ { "type" => "text", "text" => Sentence.join("Supabase could not read the logs", said) } ] }
        end

        rows = Array(inner.is_a?(Hash) ? inner["result"] : inner)
        lines = rows.filter_map do |row|
          at = Answers.time_of(row["timestamp"])
          run = row["workflow_run"].presence && "run #{row['workflow_run']}"
          text = [ run, row["error_severity"], row["level"], row["method"], row["path"], row["status_code"], row["msg"], row["error"],
                   row["event_message"] ].compact_blank.join(" ")
          Telemetry::LogLine.new(at: at, source: resource.name, text: text) if at && text.present?
        end.sort_by(&:at).reverse
        link = Telemetry::Link.new(provider: PROVIDER, url: page(resource, PAGES.fetch(source)))
        Telemetry.result(Telemetry.logs_text(lines, asked: "#{READS.fetch(source)} #{resource.name}", limit: limit), link: link)
      end

      def self.deploys_result(resource, data, given)
        migrations = Array(data.is_a?(Hash) ? data["migrations"] : data).sort_by { |migration| migration["version"].to_s }.reverse
        link = Telemetry::Link.new(provider: PROVIDER, url: page(resource, MIGRATIONS_PAGE))
        return Telemetry.result("No migrations have been applied to #{resource.name}.", link: link) if migrations.empty?

        shown = migrations.first(Answers.limit(given, DEPLOY_MOST, default: DEPLOY_LIMIT)).map do |migration|
          version = migration["version"].to_s
          at = Time.find_zone("UTC").strptime(version, "%Y%m%d%H%M%S").iso8601 if version.match?(MIGRATION_TIME)
          [ at, "migration #{version}", migration["name"].presence ].compact.join(", ")
        end
        Telemetry.result("Latest #{shown.size} of #{migrations.size} migrations applied to #{resource.name}, newest first. A migration is " \
                         "a change to its schema, named by the version it is recorded under.\n#{shown.join("\n")}", link: link)
      end

      def self.status_result(resource, data)
        return { "isError" => true, "content" => [ { "type" => "text", "text" => data.to_json } ] } unless data.is_a?(Hash)

        facts = [ ("status #{data['status']}" if data["status"]), ("region #{data['region']}" if data["region"]),
                  ("Postgres #{data.dig('database', 'version')}" if data.dig("database", "version")),
                  ("host #{data.dig('database', 'host')}" if data.dig("database", "host")), ("created #{data['created_at']}" if data["created_at"]) ]
        Telemetry.result("How #{resource.name} stands on Supabase now: #{facts.compact.join(', ')}.", link: Answers.page(resource, PROVIDER))
      end

      private_class_method :pack_project, :history, :restore, :advisors, :advisors_result
      private_class_method :ref_of, :function_route, :rollback, :function_logs, :function_logs_result, :function_result, :function_deploy
      private_class_method :scoped!, :page, :takes_project?, :project, :logs, :window, :literal, :logs_result, :deploys_result, :status_result
    end
  end
end
