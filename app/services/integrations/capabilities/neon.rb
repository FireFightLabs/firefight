module Integrations
  module Capabilities
    # Neon answers through the tools its MCP server publishes, from neondatabase/mcp-server-neon, mcp/tools/generated.
    # Each is the Neon API call of the same name and answers with the API's own objects, as @neon/tools and @neon/sdk
    # unwrap them, a list to its items. A project is the database on the map, a branch its branch, a compute the endpoint serving one.
    # Neon keeps no metrics a tool reads and no history of deploys, so status reads the computes, deploys reads the
    # operations Neon ran, and logs read what runs on a branch. Run history is those same operations, each with when it was
    # made and how long it took (the API's Operation, created_at and total_duration_ms), named by its action.
    module Neon
      extend Adapter

      PROVIDER = MapReaders::Neon::NAME
      PROVIDER_KEY = MapReaders::Neon::PROVIDER
      PROJECT_KINDS = [ ResourceMap::KIND_DATABASE, ResourceMap::KIND_BRANCH, ResourceMap::KIND_COMPUTE ].freeze
      SUPPORTS = {
        LOGS => [ ResourceMap::KIND_BRANCH ], DEPLOYS => PROJECT_KINDS, HISTORY => PROJECT_KINDS, STATUS => PROJECT_KINDS,
        RESTART => [ ResourceMap::KIND_COMPUTE ]
      }.freeze
      TOOLS = {
        LOGS => "query_logs", DEPLOYS => "list_operations", HISTORY => "list_operations", STATUS => "list_postgres_endpoints",
        RESTART => "restart_postgres_endpoint"
      }.freeze
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
      OWN_PHRASES = { RESTART => "restart a compute", HISTORY => "see how long its operations usually take" }.freeze

      def self.phrase(key) = OWN_PHRASES.fetch(key) { PHRASES.fetch(key) }

      def self.route(key, resource, given, tool: nil, settings: nil)
        project, id = ids_of(resource)
        case key
        when LOGS then logs(resource, project, id, given)
        when DEPLOYS
          Route.new(tool_name: TOOLS[DEPLOYS], arguments: { "project_id" => project, "limit" => OPERATIONS_READ },
                    present: ->(result) { Answers.read(result, PROVIDER) { |data| deploys_result(resource, id, data, given) } })
        when HISTORY
          Route.new(tool_name: TOOLS[HISTORY], arguments: { "project_id" => project, "limit" => OPERATIONS_READ },
                    present: ->(result) { Answers.read(result, PROVIDER) { |data| history_result(resource, id, data, given) } })
        when STATUS
          names = branch_names(resource, project)
          Route.new(tool_name: TOOLS[STATUS], arguments: { "project_id" => project },
                    present: ->(result) { Answers.read(result, PROVIDER) { |data| status_result(resource, id, data, names) } })
        when RESTART
          Route.new(tool_name: TOOLS[RESTART], arguments: { "project_id" => project, "endpoint_id" => id },
                    present: lambda { |result|
                      Answers.read(result, PROVIDER) do |_data|
                        Telemetry.result("Neon is restarting #{resource.name}. It suspends the compute and starts it again, so open " \
                                         "connections drop and the app reconnects.", link: Answers.page(resource, PROVIDER))
                      end
                    })
        end
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

      def self.history_result(resource, id, data, given)
        runs = operations_on(resource, id, data).map do |operation|
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

      # The project's operations on the resource, the whole project's for the database.
      def self.operations_on(resource, id, data)
        field = { ResourceMap::KIND_BRANCH => "branch_id", ResourceMap::KIND_COMPUTE => "endpoint_id" }[resource.kind]
        Array(data.is_a?(Hash) ? data["operations"] : data).select { |operation| field.nil? || operation[field] == id }
      end

      def self.deploys_result(resource, id, data, given)
        field = { ResourceMap::KIND_BRANCH => "branch_id", ResourceMap::KIND_COMPUTE => "endpoint_id" }[resource.kind]
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

      private_class_method :ids_of, :logs, :window, :logs_result, :history_result, :operations_on, :deploys_result, :status_result, :compute_line, :suspends, :branch_names
    end
  end
end
