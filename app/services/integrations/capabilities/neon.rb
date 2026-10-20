module Integrations
  module Capabilities
    # Neon answers through the tools its MCP server publishes, from neondatabase/mcp-server-neon, mcp/tools/generated.
    # Each is the Neon API call of the same name and answers with the API's own objects, as @neon/tools and @neon/sdk
    # unwrap them, a list to its items. A project is the database on the map, a branch its branch, a compute the endpoint
    # serving one and a Neon Function a function on a branch. Neon keeps no metrics a tool reads and no history of deploys,
    # so status reads the computes, deploys reads the operations Neon ran, and logs read what runs on a branch. Run history
    # is those same operations, each with when it was made and how long it took (the API's Operation, created_at and
    # total_duration_ms), named by its action, and one run asked by its id is read with get_operation however old it is.
    # Errors are the slowest queries pg_stat_statements holds, through list_slow_queries. A branch rolls back to a
    # snapshot (restore_snapshot, finalized so its computes move onto the restored data) or to its parent's current state
    # (reset_from_parent), the two restores the server publishes (@neon/tools, lib/ergonomic/composed.js), or to its own
    # state at a moment or an LSN through Firefight's restore_branch on the Neon API (Packs::Neon), which the server does
    # not offer. A project's metrics are its consumption, compute time and data sent out, through Firefight's
    # consumption_history on the same API. Both need a connection made with an organization API key. A compute restarts, or starts when it is suspended, and is resized in
    # compute units through update_postgres_endpoint. A function's status and deploys are its latest and serving
    # deployments, through get_function (the API's NeonFunction).
    module Neon
      extend Adapter

      PROVIDER = MapReaders::Neon::NAME
      PROVIDER_KEY = MapReaders::Neon::PROVIDER
      PROJECT_KINDS = [ ResourceMap::KIND_DATABASE, ResourceMap::KIND_BRANCH, ResourceMap::KIND_COMPUTE ].freeze
      READ_KINDS = [ *PROJECT_KINDS, ResourceMap::KIND_FUNCTION ].freeze
      SUPPORTS = {
        LOGS => [ ResourceMap::KIND_BRANCH ], DEPLOYS => READ_KINDS, HISTORY => PROJECT_KINDS, STATUS => READ_KINDS, ERRORS => PROJECT_KINDS,
        ROLLBACK => [ ResourceMap::KIND_BRANCH ], RESTART => [ ResourceMap::KIND_COMPUTE ], SCALE => [ ResourceMap::KIND_COMPUTE ],
        METRICS => [ ResourceMap::KIND_DATABASE ]
      }.freeze
      LIST_OPERATIONS = "list_operations".freeze
      GET_OPERATION = "get_operation".freeze
      RESTORE_SNAPSHOT = "restore_snapshot".freeze
      RESET_FROM_PARENT = "reset_from_parent".freeze
      RESTART_COMPUTE = "restart_postgres_endpoint".freeze
      START_COMPUTE = "start_postgres_endpoint".freeze
      UPDATE_COMPUTE = "update_postgres_endpoint".freeze
      SLOW_QUERIES = "list_slow_queries".freeze
      GET_FUNCTION = "get_function".freeze
      LIST_COMPUTES = "list_postgres_endpoints".freeze
      RESTORE_BRANCH = "restore_branch".freeze
      CONSUMPTION = "consumption_history".freeze
      TOOLS = {
        LOGS => "query_logs", DEPLOYS => [ LIST_OPERATIONS, GET_FUNCTION ], HISTORY => [ LIST_OPERATIONS, GET_OPERATION ],
        STATUS => [ LIST_COMPUTES, GET_FUNCTION ], ERRORS => SLOW_QUERIES, ROLLBACK => [ RESTORE_SNAPSHOT, RESET_FROM_PARENT, RESTORE_BRANCH ],
        RESTART => [ RESTART_COMPUTE, START_COMPUTE ], SCALE => UPDATE_COMPUTE, METRICS => CONSUMPTION
      }.freeze
      # The metric names every capability uses that a project's consumption answers honestly: compute time as
      # compute_unit_seconds and data sent out as public_network_transfer_bytes. Its storage counts in byte-months, which
      # is no level of disk, so it is read with consumption_history itself.
      CONSUMPTION_METRICS = { "cpu_time" => "compute_unit_seconds", "network_out" => "public_network_transfer_bytes" }.freeze
      # A moment a branch is restored to, an ISO 8601 time, and a Postgres LSN.
      MOMENT = /\A\d{4}-\d{2}-\d{2}T/
      LSN = %r{\A\h{1,8}/\h{1,8}\z}
      # A suspended compute in Firefight's words (Providers::Neon status_words, from Neon's idle), which starts rather than restarts.
      SUSPENDED = "sleeping".freeze
      # The compute sizes Neon offers, in compute units (neon.com/docs/manage/endpoints, Compute size and autoscaling
      # configuration). Autoscaling runs between 0.25 and 16 CU, at most 8 CU apart, and larger sizes are fixed only.
      SIZES = [ 0.25, 0.5, *(1..16), *(18..56).step(2) ].map(&:to_f).freeze
      AUTOSCALING_MOST = 16
      AUTOSCALING_SPREAD = 8
      PLAN = /\A\s*(\d+(?:\.\d+)?)\s*(?:-\s*(\d+(?:\.\d+)?)\s*)?\z/
      # A function deployment's status in the API's own words (NeonFunctionDeployment), in the words every run history uses.
      DEPLOYMENT_STATUSES = {
        "pending" => History::QUEUED, "building" => History::RUNNING, "completed" => History::SUCCEEDED, "failed" => History::FAILED
      }.freeze
      # list_slow_queries reads this many by default, and the capability asks for at most this many.
      SLOW_LIMIT = 10
      SLOW_MOST = 50
      # What a rollback names to go back to the parent's current state rather than to a snapshot.
      PARENT = "parent".freeze
      # What reset_from_parent keeps a branch with children under, and the month, day, hour and minute its name ends with.
      PRESERVE = "preserve_under_name".freeze
      KEPT_STAMP = "%m%d%H%M".freeze
      # An operation's status in the API's own words (OperationStatus), in the words every run history uses.
      OPERATION_STATUSES = {
        "scheduling" => History::QUEUED, "running" => History::RUNNING, "cancelling" => History::RUNNING, "finished" => History::SUCCEEDED,
        "skipped" => History::SUCCEEDED, "failed" => History::FAILED, "error" => History::FAILED, "cancelled" => History::CANCELLED
      }.freeze
      # Neon's tools reach every project the account sees, far beyond the map, so they stay offered as they are.
      WRAPPED = [].freeze
      # query_logs takes at most 1000 a call and a window of at most seven days.
      LOG_LIMIT = 200
      LOG_MOST = 1_000
      # list_operations answers the project's operations newest first, so the latest are read and those on the resource kept.
      OPERATIONS_READ = 200
      DEPLOY_LIMIT = 20
      DEPLOY_MOST = 100

      # A restart here is of a compute, which Neon suspends and starts again, and its runs are the operations it ran.
      OWN_PHRASES = {
        RESTART => "restart a compute or start a suspended one", HISTORY => "see how long its operations usually take",
        ROLLBACK => "roll a branch back to a moment, a snapshot or its parent", ERRORS => "read its slowest queries", SCALE => "resize a compute",
        METRICS => "read a project's compute time and data sent out"
      }.freeze

      def self.phrase(key) = OWN_PHRASES.fetch(key) { PHRASES.fetch(key) }

      # A compute is sized in compute units rather than copies, so scale takes a plan.
      def self.takes_plan? = true

      def self.route(key, resource, given, tool: nil, settings: nil)
        return function_route(key, resource, given) if resource.kind == ResourceMap::KIND_FUNCTION

        project, id = ids_of(resource)
        case key
        when LOGS then logs(resource, project, id, given)
        when DEPLOYS
          Route.new(tool_name: LIST_OPERATIONS, arguments: { "project_id" => project, "limit" => OPERATIONS_READ },
                    present: ->(result) { Answers.read(result, PROVIDER) { |data| deploys_result(resource, id, data, given) } })
        when HISTORY then history(resource, project, id, given)
        when ROLLBACK then rollback(resource, project, id, given)
        when METRICS then consumption(project, given)
        when STATUS
          names = branch_names(resource, project)
          Route.new(tool_name: LIST_COMPUTES, arguments: { "project_id" => project },
                    present: ->(result) { Answers.read(result, PROVIDER) { |data| status_result(resource, id, data, names) } })
        when RESTART then restart(resource, project, id)
        when SCALE then scale(resource, project, id, given)
        when ERRORS then slow_queries(resource, project, id, given)
        end
      end

      # A suspended compute is started, since nothing is connected to one to restart. The map's state decides, which live
      # updates keep within minutes.
      def self.restart(resource, project, id)
        page = Answers.page(resource, PROVIDER)
        if Provider.for(PROVIDER_KEY).status_of(resource.status) == SUSPENDED
          return Route.new(tool_name: START_COMPUTE, arguments: { "project_id" => project, "endpoint_id" => id },
                           present: lambda { |result|
                             Answers.read(result, PROVIDER) do |_data|
                               Telemetry.result("Neon is starting #{resource.name}, which was suspended. It takes connections again once it is active.", link: page)
                             end
                           })
        end

        Route.new(tool_name: RESTART_COMPUTE, arguments: { "project_id" => project, "endpoint_id" => id },
                  present: lambda { |result|
                    Answers.read(result, PROVIDER) do |_data|
                      Telemetry.result("Neon is restarting #{resource.name}. It suspends the compute and starts it again, so open " \
                                       "connections drop and the app reconnects.", link: page)
                    end
                  })
      end

      # A plan is one size, such as 2, or an autoscaling range, such as 0.25-4, in compute units. Neon restarts the compute
      # to apply either (neon.com/docs/manage/endpoints).
      def self.scale(resource, project, id, given)
        sizing = "Give plan as a size in compute units, such as 2, or an autoscaling range, such as 0.25-4."
        if given["instances"].present?
          raise Unroutable, "A Neon compute runs as one and grows in compute units rather than copies, so leave instances out. #{sizing}"
        end

        low, high = sizes(given[PLAN_ARG], sizing)
        Route.new(tool_name: UPDATE_COMPUTE,
                  arguments: { "project_id" => project, "endpoint_id" => id, "autoscaling_limit_min_cu" => low, "autoscaling_limit_max_cu" => high },
                  present: lambda { |result|
                    Answers.read(result, PROVIDER) do |_data|
                      size = low == high ? "a fixed #{cu(low)} CU" : "autoscale between #{cu(low)} and #{cu(high)} CU"
                      Telemetry.result("Neon set #{resource.name} to #{size}. It restarts the compute to apply it, so open connections drop " \
                                       "for a moment and the app reconnects.", link: Answers.page(resource, PROVIDER))
                    end
                  })
      end

      def self.sizes(plan, sizing)
        found = plan.to_s.match(PLAN)
        raise Unroutable, sizing unless found

        low = found[1].to_f
        high = (found[2] || found[1]).to_f
        unknown = [ low, high ].uniq.reject { |size| SIZES.include?(size) }
        raise Unroutable, "Neon offers no #{unknown.map { |size| cu(size) }.join(' or ')} CU compute. It offers #{SIZES.map { |size| cu(size) }.join(', ')}." if unknown.any?
        raise Unroutable, "The smaller size goes first, such as 0.25-4." if low > high
        if low != high && (high > AUTOSCALING_MOST || high - low > AUTOSCALING_SPREAD)
          raise Unroutable, "Neon autoscales between 0.25 and #{AUTOSCALING_MOST} CU, at most #{AUTOSCALING_SPREAD} CU apart. Larger sizes are fixed, such as 20."
        end

        [ low, high ]
      end

      # 2.0 reads as 2, and 0.25 as it is.
      def self.cu(size) = size == size.to_i ? size.to_i.to_s : size.to_s

      # The slowest queries pg_stat_statements holds for the project's default branch, a branch or one compute.
      def self.slow_queries(resource, project, id, given)
        # Text is matched here, so the most the tool gives are read for it, and the answer cut to the limit after.
        arguments = { "project_id" => project, "limit" => given["text"].present? ? SLOW_MOST : Answers.limit(given, SLOW_MOST, default: SLOW_LIMIT) }
        arguments["branch_id"] = id if resource.kind == ResourceMap::KIND_BRANCH
        arguments["compute_id"] = id if resource.kind == ResourceMap::KIND_COMPUTE
        Route.new(tool_name: SLOW_QUERIES, arguments: arguments,
                  present: ->(result) { Answers.read(result, PROVIDER) { |data| slow_queries_result(resource, data, given) } })
      end

      # The server's answer (mcp/tools/tools.ts, handleListSlowQueries) lists slow_queries by mean time, with calls, total
      # and mean time in milliseconds and rows. pg_stat_statements counts since its statistics were last reset, so no time
      # range narrows it.
      def self.slow_queries_result(resource, data, given)
        queries = Array(data.is_a?(Hash) ? data["slow_queries"] : data).select { |query| query.is_a?(Hash) && query["query"].present? }
        read = queries.size
        if given["text"].present?
          queries = queries.select { |query| query["query"].downcase.include?(given["text"].downcase) }.first(Answers.limit(given, SLOW_MOST, default: SLOW_LIMIT))
        end
        link = Answers.page(resource, PROVIDER)
        what = given["text"].present? ? " containing #{given['text']}" : ""
        if queries.empty?
          among = given["text"].present? ? " among its #{read} slowest" : ""
          return Telemetry.result("pg_stat_statements holds no slow queries#{what}#{among} for #{resource.name}.", link: link)
        end

        lines = queries.map do |query|
          [ "#{query['mean_exec_time_ms'].to_f.round(1)}ms on average", "#{query['calls']} calls", "#{query['total_exec_time_ms'].to_f.round}ms in all",
            ("#{query['rows']} rows" if query["rows"]), query["query"].to_s.squish.truncate(300) ].compact.join(", ")
        end
        Telemetry.result("The #{lines.size} slowest queries#{what} on #{resource.name} by average time, from pg_stat_statements since its " \
                         "statistics were last reset:\n#{lines.join("\n")}", link: link)
      end

      # A function is project/branch/slug on the map, and get_function reads it with its latest and its serving deployment.
      def self.function_route(key, resource, _given)
        project, branch, slug = resource.external_id.to_s.split("/", 3)
        raise Unroutable, "#{resource.name} is not named the way Neon's map sweep names it, so it cannot be asked for this." if slug.blank?

        Route.new(tool_name: GET_FUNCTION, arguments: { "project_id" => project, "branch_id" => branch, "slug" => slug },
                  present: ->(result) { Answers.read(result, PROVIDER) { |data| function_result(resource, data, key) } })
      end

      def self.function_result(resource, data, key)
        function = data.is_a?(Hash) && data["function"].is_a?(Hash) ? data["function"] : data
        link = Answers.page(resource, PROVIDER)
        return Telemetry.result("Neon answered #{resource.name} in a shape Firefight does not read.", link: link) unless function.is_a?(Hash)

        current, active = function.values_at("current_deployment", "active_deployment").map { |each| each if each.is_a?(Hash) }
        return function_deploys(resource, current, active, link) if key == DEPLOYS

        facts = [ ("serving version #{active['id']}" if active), ("latest version #{current['id']} #{current['status']}" if current && current["id"] != active&.dig("id")),
                  ("its latest build failed (#{current['error']})" if current && current["status"] == "failed" && current["error"].present?),
                  ("invoked at #{function['invocation_url']}" if function["invocation_url"].present?) ].compact
        facts.unshift("no deployment yet") if current.nil? && active.nil?
        Telemetry.result("How #{resource.name} stands on Neon now: #{facts.join(', ')}.", link: link)
      end

      # Neon keeps a function's latest deployment and the one serving, which is the latest that built.
      def self.function_deploys(resource, current, active, link)
        deployments = [ current, active ].compact.uniq { |each| each["id"] }
        return Deploys.with_deploys(Telemetry.result("#{resource.name} has no deployment yet.", link: link), []) if deployments.empty?

        lines = deployments.map do |deployment|
          [ "version #{deployment['id']}", deployment["status"], ("serving" if deployment["id"] == active&.dig("id")), deployment["created_at"],
            deployment["runtime"], ("#{deployment['memory_mib']} MiB" if deployment["memory_mib"]),
            ("failed (#{deployment['error']})" if deployment["error"].present?) ].compact.join(", ")
        end
        result = Telemetry.result("Deployments of #{resource.name}, newest first. Neon keeps the latest deployment and the one serving, so " \
                                  "earlier ones are not listed.\n#{lines.join("\n")}", link: link)
        deploys = deployments.map do |deployment|
          Deploys::Deploy.new(id: deployment["id"], version: deployment["id"], status: Deploys.status(deployment["status"], DEPLOYMENT_STATUSES),
                              live: active.present? && deployment["id"] == active["id"], started_at: deployment["created_at"])
        end
        Deploys.with_deploys(result, deploys)
      end

      # The resource's recent operations, or one by its id through get_operation, so a watch follows a run past the
      # project's latest operations.
      def self.history(resource, project, id, given)
        run = given["run"].to_s.strip.presence
        if run
          return Route.new(tool_name: GET_OPERATION, arguments: { "project_id" => project, "operation_id" => run },
                           present: ->(result) { Answers.read(result, PROVIDER) { |data| history_result(resource, [ operation_of(data) ], given.except("name")) } })
        end

        Route.new(tool_name: LIST_OPERATIONS, arguments: { "project_id" => project, "limit" => OPERATIONS_READ },
                  present: ->(result) { Answers.read(result, PROVIDER) { |data| history_result(resource, operations_on(resource, id, data), given) } })
      end

      # get_operation answers the API's OperationResponse, the operation under its own key.
      def self.operation_of(data) = data.is_a?(Hash) && data["operation"].is_a?(Hash) ? data["operation"] : data

      # Back to a snapshot by its id, as list_snapshots gives it, or to the parent's current state. A snapshot restored
      # onto the branch is finalized, since that moves the branch's computes onto it and nothing serves the older data
      # otherwise.
      def self.rollback(resource, project, branch, given)
        to = given["to"].to_s.strip
        if to.empty?
          raise Unroutable, "Say what to roll #{resource.name} back to: a moment as an ISO 8601 time with a zone, a Postgres LSN, a " \
                            "snapshot's id, as list_snapshots gives it, or #{PARENT} for its parent's current state."
        end
        return restore(resource, project, branch, to) if to.match?(MOMENT) || to.match?(LSN)

        page = Answers.page(resource, PROVIDER)
        if to.casecmp?(PARENT)
          kept = kept_branch(resource, project, branch)
          return Route.new(tool_name: RESET_FROM_PARENT, arguments: { "project_id" => project, "branch_id" => branch, PRESERVE => kept }.compact,
                           keeps: (kept && "its current state as branch #{kept}"),
                           present: lambda { |result|
                             Answers.read(result, PROVIDER) do |_data|
                               words = kept ? "Its state before is kept as branch #{kept}, which its child branches now hang from." : "What it wrote since it branched is gone."
                               Telemetry.result("Neon reset #{resource.name} to its parent's current state. #{words} Its computes restart, so " \
                                                "open connections drop.", link: page)
                             end
                           })
        end

        Route.new(tool_name: RESTORE_SNAPSHOT, arguments: { "project_id" => project, "snapshot_id" => to, "target_branch_id" => branch, "finalize" => true },
                  present: lambda { |result|
                    Answers.read(result, PROVIDER) do |_data|
                      Telemetry.result("Neon restored snapshot #{to} onto #{resource.name} and moved its computes onto it, so open " \
                                       "connections drop and the app reconnects to the restored data.", link: page)
                    end
                  })
      end

      # Back to the branch's own state at a moment or an LSN, through restore_branch on the Neon API. Neon requires the
      # current state kept under a name when a branch is restored from itself, and its child branches move onto that one,
      # so the name is always given. The pack checks the moment has a zone and has passed, and answers in its own words.
      def self.restore(resource, project, branch, to)
        kept = "#{resource.name.split('/').last}-before-rollback-#{Time.current.utc.strftime(KEPT_STAMP)}"
        point = to.match?(LSN) ? { Packs::Neon::LSN => to } : { Packs::Neon::TIMESTAMP => to }
        Route.new(tool_name: RESTORE_BRANCH, arguments: { "project_id" => project, "branch_id" => branch, PRESERVE => kept }.merge(point),
                  keeps: "its current state as branch #{kept}")
      end

      # A project's compute time and data sent out from its consumption, in the names every capability uses.
      def self.consumption(project, given)
        metrics = metric_names(given, CONSUMPTION_METRICS, PROVIDER).presence || CONSUMPTION_METRICS.values
        Route.new(tool_name: CONSUMPTION, arguments: { "project_id" => project, "metrics" => metrics }.merge(given.slice("minutes", "start", "end").compact_blank))
      end

      # Neon resets a branch that has children only when its current state is kept under a name (reset_from_parent,
      # preserve_under_name), and the children move onto that branch. The name says what it was and when, such as
      # main-before-rollback-10111530. nil for a branch the map holds no children of.
      def self.kept_branch(resource, project, branch)
        children = ResourceMap::Resource.present.where(workspace_id: resource.workspace_id, provider: resource.provider, kind: ResourceMap::KIND_BRANCH)
                                        .where("external_id LIKE ?", "#{ResourceMap::Resource.sanitize_sql_like(project)}/%")
                                        .where("details ->> ? = ?", MapReaders::Neon::PARENT_DETAIL, branch)
        return unless children.exists?

        "#{resource.name.split('/').last}-before-rollback-#{Time.current.utc.strftime(KEPT_STAMP)}"
      end

      # The project's id and the branch's or compute's own, as the map's reader writes them, project/id.
      def self.ids_of(resource)
        return [ resource.external_id, nil ] if resource.kind == ResourceMap::KIND_DATABASE

        project, id = resource.external_id.to_s.split("/", 2)
        raise Unroutable, "#{resource.name} is not named the way Neon's map sweep names it, so it cannot be asked for this." if id.blank?

        [ project, id ]
      end

      def self.logs(resource, project, branch, given)
        raise Unroutable, "Neon's log search finds text, not a regular expression. Give text instead." if given["regex"].present?
        raise Unroutable, "Neon's log search cannot leave lines out. Give the text to look for instead." if given["exclude"].present?
        raise Unroutable, "Neon keeps what runs on a branch prints, so stream must be #{STREAM_APP}." unless given["stream"].in?([ nil, "", STREAM_APP ])

        limit = Answers.limit(given, LOG_MOST, default: LOG_LIMIT)
        arguments = { "project_id" => project, "branch_id" => branch, "limit" => limit, "sort_order" => "desc" }
        arguments["body_contains"] = given["text"] if given["text"].present?
        Route.new(tool_name: TOOLS[LOGS], arguments: arguments.merge(window(given)),
                  present: ->(result) { Answers.read(result, PROVIDER) { |data| logs_result(resource, data, limit) } })
      end

      # Minutes alone go as Neon's relative window, such as since 30m, so the same request reads the same each time. A start or
      # end goes as ISO 8601 in UTC, which is the only form query_logs takes.
      def self.window(given)
        minutes = Answers.minutes(given)
        return { "since" => "#{minutes}m" } if minutes

        started, ended = Answers.range(given)
        { "start_time" => started.utc.iso8601, "end_time" => ended.utc.iso8601 }
      end

      def self.logs_result(resource, data, limit)
        records = data.is_a?(Hash) ? data["logs"] : data
        lines = Array(records).filter_map do |record|
          at = Telemetry.parse_time(record["timestamp"])
          text = [ record["severity_text"], record["message"] ].compact_blank.join(" ")
          Telemetry::LogLine.new(at: at, source: record["service_name"].presence || record["source"].presence || resource.name, text: text) if at && text.present?
        end.sort_by(&:at).reverse
        text = Telemetry.logs_text(lines, asked: "branch #{resource.name}", limit: limit)
        # From Neon's own logs guide, neondatabase/agent-skills, skills/neon/references/logs-loki.md.
        text += " Neon keeps logs for the Functions and Object Storage on a branch, and Postgres does not write to them yet." if lines.empty?
        Telemetry.result(text, link: Answers.page(resource, PROVIDER))
      end

      def self.history_result(resource, operations, given)
        runs = operations.select { |operation| operation.is_a?(Hash) && operation["id"].present? }.map do |operation|
          status = History.status(operation["status"], OPERATION_STATUSES)
          started = Telemetry.parse_time(operation["created_at"])
          took = operation["total_duration_ms"]
          History::Run.new(
            id: operation["id"], name: operation["action"], status: status, started_at: started,
            finished_at: (started + (took.to_f / 1000) if started && took && History::FINISHED.include?(status)),
            detail: operation["error"].presence&.to_s&.truncate(200)
          )
        end
        History.result(runs, what: resource.name, link: Answers.page(resource, PROVIDER), name: given["name"],
                             limit: Answers.limit(given, History::LIMIT))
      end

      # The field of an operation naming the resource it ran on, by the resource's kind. A database has none.
      OPERATION_FIELDS = { ResourceMap::KIND_BRANCH => "branch_id", ResourceMap::KIND_COMPUTE => "endpoint_id" }.freeze

      # The project's operations on the resource, the whole project's for the database.
      def self.operations_on(resource, id, data)
        field = OPERATION_FIELDS[resource.kind]
        Array(data.is_a?(Hash) ? data["operations"] : data).select { |operation| field.nil? || operation[field] == id }
      end

      def self.deploys_result(resource, id, data, given)
        field = OPERATION_FIELDS[resource.kind]
        operations = operations_on(resource, id, data)
        operations = operations.sort_by { |operation| operation["created_at"].to_s }.reverse.first(Answers.limit(given, DEPLOY_MOST, default: DEPLOY_LIMIT))
        link = Answers.page(resource, PROVIDER)
        if operations.empty?
          return Telemetry.result("Neon ran no operations on #{resource.name} among the project's latest #{OPERATIONS_READ}.", link: link)
        end

        lines = operations.map do |operation|
          [ operation["created_at"], operation["action"].to_s.tr("_", " "), operation["status"],
            ("on branch #{operation['branch_id']}" if operation["branch_id"] && field != "branch_id"),
            ("on compute #{operation['endpoint_id']}" if operation["endpoint_id"] && field != "endpoint_id"),
            ("took #{(operation['total_duration_ms'].to_f / 1000).round(1)}s" if operation["total_duration_ms"]),
            ("failed (#{operation['error']})" if operation["error"].present?) ].compact.join(", ")
        end
        Telemetry.result("Latest #{lines.size} operations Neon ran on #{resource.name}, newest first. Neon has no deploys of its own, " \
                         "so these are the changes it made, such as starting or suspending a compute, applying its configuration " \
                         "or creating a branch.\n#{lines.join("\n")}", link: link)
      end

      def self.status_result(resource, id, data, names)
        endpoints = Array(data.is_a?(Hash) ? data["endpoints"] : data)
        endpoints = endpoints.select { |endpoint| endpoint["branch_id"] == id } if resource.kind == ResourceMap::KIND_BRANCH
        endpoints = endpoints.select { |endpoint| endpoint["id"] == id } if resource.kind == ResourceMap::KIND_COMPUTE
        link = Answers.page(resource, PROVIDER)
        return Telemetry.result("No compute serves #{resource.name}, so nothing can connect to it until one is added.", link: link) if endpoints.empty?

        lines = endpoints.map { |endpoint| compute_line(endpoint, names) }
        Telemetry.result("How #{resource.name} stands on Neon now, by the computes that serve it:\n#{lines.join("\n")}", link: link)
      end

      def self.compute_line(endpoint, names)
        state = endpoint["disabled"] ? "disabled" : endpoint["current_state"]
        state = "#{state}, going #{endpoint['pending_state']}" if endpoint["pending_state"].present?
        [ "compute #{endpoint['id']} (#{endpoint['type'].to_s.tr('_', ' ')})", "on branch #{names.fetch(endpoint['branch_id'], endpoint['branch_id'])}",
          state, ("#{endpoint['autoscaling_limit_min_cu']} to #{endpoint['autoscaling_limit_max_cu']} CU" if endpoint["autoscaling_limit_max_cu"]),
          suspends(endpoint["suspend_timeout_seconds"]), ("last active #{endpoint['last_active']}" if endpoint["last_active"]),
          ("started #{endpoint['started_at']}" if endpoint["started_at"]), ("suspended #{endpoint['suspended_at']}" if endpoint["suspended_at"]),
          ("pooler #{endpoint['pooler_mode']}" if endpoint["pooler_enabled"]) ].compact.join(", ")
      end

      # In the API's suspend_timeout_seconds, 0 is the project's default and -1 never suspends.
      def self.suspends(seconds)
        case seconds
        when nil then nil
        when -1 then "never suspends"
        when 0 then "suspends when idle after the default time"
        else "suspends after #{seconds}s idle"
        end
      end

      # The branch names the map knows for the project, so a compute reads by its branch's name rather than its id.
      def self.branch_names(resource, project)
        ResourceMap::Resource.where(workspace_id: resource.workspace_id, provider: PROVIDER_KEY, kind: ResourceMap::KIND_BRANCH)
                             .where("external_id LIKE ?", "#{ResourceMap::Resource.sanitize_sql_like(project)}/%").pluck(:external_id, :name)
                             .to_h { |external_id, name| [ external_id.split("/", 2).last, name ] }
      end

      private_class_method :restart, :scale, :sizes, :cu, :slow_queries, :slow_queries_result, :function_route, :function_result,
                           :function_deploys, :history, :operation_of, :rollback, :restore, :consumption, :kept_branch, :ids_of, :logs, :window, :logs_result, :history_result, :operations_on, :deploys_result, :status_result, :compute_line, :suspends, :branch_names
    end
  end
end
