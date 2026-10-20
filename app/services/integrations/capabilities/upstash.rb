module Integrations
  module Capabilities
    # Upstash answers through its remote MCP server at mcp.upstash.com. Upstash's docs, agent-resources/mcp, name the
    # server's tools and say every QStash tool takes a region and a service. They publish no other parameter, so the
    # arguments follow the parameters the connected tool reports, as for Datadog, and Firefight never sends one it does
    # not report. Answers are read as Upstash's Developer and QStash APIs document them in DatabaseStats, LogEntry and
    # DLQMessage, and filtered here by time and text where the tool takes no such filter. An answer in another shape
    # reaches the agent as it came. A Redis database answers status and metrics, and the QStash of a region answers its
    # delivery logs, and its dead letter queue as errors. A workflow answers its runs through logs_list with service
    # workflow, read as the Workflow API's WorkflowRun (workflow/api-reference/logs/list-workflow-run-logs), and one run by
    # its workflowRunId with its steps. A Box answers what it printed through box_logs, read as the Box SDK's LogEntry
    # (@upstash/box 0.7.10), and its CPU, memory and disk through box_metrics, whose answer Upstash does not document, so
    # that one reaches the agent as it came. A Redis database rolls back to one of its backups through Firefight's own
    # restore_redis_backup, by the backup's id as redis_list_backups gives it.
    module Upstash
      extend Adapter

      PROVIDER = "Upstash".freeze
      PROVIDER_KEY = "upstash".freeze
      GET_DATABASE = "redis_get_database".freeze
      GET_STATS = "redis_get_stats".freeze
      LIST_LOGS = "logs_list".freeze
      LIST_DLQ = "dlq_list".freeze
      BOX_LOGS = "box_logs".freeze
      BOX_METRICS = "box_metrics".freeze
      # Firefight's own restore through the Developer API (Packs::Upstash), beside the server's tools.
      RESTORE_BACKUP = "restore_redis_backup".freeze
      SUPPORTS = {
        STATUS => [ ResourceMap::KIND_DATABASE ], METRICS => [ ResourceMap::KIND_DATABASE, ResourceMap::KIND_VIRTUAL_MACHINE ],
        LOGS => [ ResourceMap::KIND_QUEUE, ResourceMap::KIND_VIRTUAL_MACHINE ], ERRORS => [ ResourceMap::KIND_QUEUE ],
        HISTORY => [ ResourceMap::KIND_WORKFLOW ], ROLLBACK => [ ResourceMap::KIND_DATABASE ]
      }.freeze
      TOOLS = {
        STATUS => GET_DATABASE, METRICS => [ GET_STATS, BOX_METRICS ], LOGS => [ LIST_LOGS, BOX_LOGS ], ERRORS => LIST_DLQ, HISTORY => LIST_LOGS,
        ROLLBACK => RESTORE_BACKUP
      }.freeze
      # Their arguments are read off the connected tools, so they stay offered for when they cannot be.
      WRAPPED = [].freeze
      DATABASE = %w[database_id id].freeze
      REGION = "region".freeze
      SERVICE = "service".freeze
      QSTASH = "qstash".freeze
      WORKFLOW = "workflow".freeze
      # A workflow's address, which the map keeps, and the run filters the Workflow API's logs read takes.
      WORKFLOW_URL = "workflowUrl".freeze
      WORKFLOW_RUN = "workflowRunId".freeze
      BOX = %w[box_id id].freeze
      ACTION = "action".freeze
      # box_metrics reads a box's CPU, memory and disk over time with this action, as Upstash's MCP docs name it.
      BOX_HISTORY = "history".freeze
      BOX_METRIC_NAMES = %w[cpu memory disk].freeze
      BOX_LOG_MOST = 1_000
      # A workflow run's state (WorkflowRun.workflowState) and a step's (StepInfo.state), in the words every history uses.
      RUN_STATUSES = {
        "run_started" => History::RUNNING, "run_success" => History::SUCCEEDED, "run_failed" => History::FAILED, "run_canceled" => History::CANCELLED,
        "step_success" => History::SUCCEEDED, "step_retry" => History::RUNNING, "step_progress" => History::RUNNING,
        "step_failed" => History::FAILED, "step_canceled" => History::CANCELLED
      }.freeze
      # The Workflow API lists at most ten runs a page when it groups them by run.
      RUNS_READ = 10
      COUNT = %w[count limit page_size].freeze
      PERIOD = "period".freeze
      # The periods Upstash's stats are read over, in hours, as its own server names them.
      PERIODS = { "1h" => 1, "3h" => 3, "12h" => 12, "1d" => 24, "3d" => 72, "7d" => 168 }.freeze
      LOG_LIMIT = 200
      ERROR_LIMIT = 200
      # DatabaseStats keeps each of these as a list of points, x the time and y the value.
      Metric = Data.define(:field, :title, :unit, :scale)
      METRICS_READ = {
        "requests" => Metric.new(field: "throughput", title: "Commands", unit: "per second", scale: 1),
        "tcp_connections" => Metric.new(field: "connection_count", title: "Connections", unit: "count", scale: 1),
        "disk" => Metric.new(field: "diskusage", title: "Data size", unit: "MB", scale: 1.0 / 1_048_576)
      }.freeze

      OWN_PHRASES = { HISTORY => "follow a workflow's runs", LOGS => "read QStash delivery logs and what a Box printed",
                      METRICS => "read a Redis database's or a Box's metrics", ROLLBACK => "restore a Redis database from one of its backups" }.freeze

      def self.phrase(key) = OWN_PHRASES.fetch(key) { PHRASES.fetch(key) }

      def self.route(key, resource, given, tool: nil, settings: nil)
        return box_route(key, resource, given, tool) if resource.kind == ResourceMap::KIND_VIRTUAL_MACHINE

        case key
        when STATUS then Route.new(tool_name: GET_DATABASE, arguments: database(resource, tool))
        when METRICS then metrics(resource, given, tool)
        when LOGS then logs(resource, given, tool)
        when ERRORS then errors(resource, given, tool)
        when HISTORY then history(resource, given, tool)
        when ROLLBACK
          Route.new(tool_name: RESTORE_BACKUP, arguments: { Packs::Upstash::DATABASE => resource.external_id, Packs::Upstash::BACKUP => target(given) })
        end
      end

      # A box is read through the Box tools, so those are the tools whose arguments its route is handed.
      BOX_TOOLS = { LOGS => BOX_LOGS, METRICS => BOX_METRICS }.freeze

      def self.tool_for(key, kind = nil) = kind == ResourceMap::KIND_VIRTUAL_MACHINE && BOX_TOOLS.key?(key) ? BOX_TOOLS[key] : super

      def self.box_route(key, resource, given, tool)
        raise Unroutable, "#{BOX_TOOLS[key]} is switched off for this Upstash connection. An admin can switch it on in Integrations." unless tool

        key == LOGS ? box_logs(resource, given, tool) : box_metrics(resource, given, tool)
      end

      def self.database(resource, tool)
        name = Answers.named(tool, DATABASE)
        raise Unroutable, "Upstash's tool takes the database in a way Firefight does not know yet, so ask it with Upstash's own tool." unless name

        { name => resource.external_id }
      end

      # The region and the service a QStash tool takes, as Upstash's docs say every one does.
      def self.qstash(resource, tool)
        properties = Answers.properties(tool).to_h
        region = resource.details.to_h[REGION].presence
        raise Unroutable, "The QStash region of #{resource.name} is not known, so it cannot be asked for this." unless region
        unless properties.key?(REGION)
          raise Unroutable, "Upstash's QStash tool takes its region in a way Firefight does not know yet, so ask it with Upstash's own tool."
        end

        { REGION => region, SERVICE => (QSTASH if properties.key?(SERVICE)) }.compact
      end

      def self.metrics(resource, given, tool)
        metric_names(given, METRICS_READ.transform_values(&:field), PROVIDER)
        names = Array(given["metrics"]).map(&:to_s).uniq.presence || METRICS_READ.keys
        started, ended = Answers.range(given)
        arguments = database(resource, tool)
        period = period_for(Answers.properties(tool).to_h, (((Time.current - started) / 60.0).round / 60.0).ceil)
        arguments[PERIOD] = period if period
        Route.new(tool_name: GET_STATS, arguments: arguments,
                  present: ->(result) { Answers.read(result, PROVIDER) { |data| metrics_result(result, resource, data, names, started, ended) } })
      end

      # The shortest period the tool offers that reaches back to the start, or its longest.
      def self.period_for(properties, hours)
        offered = Array(properties.dig(PERIOD, "enum")).map(&:to_s) & PERIODS.keys
        return nil if offered.empty?

        offered.sort_by { |period| PERIODS.fetch(period) }.find { |period| PERIODS.fetch(period) >= hours } || offered.max_by { |period| PERIODS.fetch(period) }
      end

      def self.logs(resource, given, tool)
        raise Unroutable, "Upstash keeps the delivery log of each QStash message, so stream must be app or requests." unless given["stream"].in?([ nil, "", STREAM_APP, "requests" ])
        raise Unroutable, "Upstash's logs are searched by text, not by a regular expression. Give text instead." if given["regex"].present?

        limit = Answers.limit(given, LOG_LIMIT)
        arguments = qstash(resource, tool)
        count = Answers.named(tool, COUNT)
        arguments[count] = limit if count
        started, ended = Answers.range(given)
        Route.new(tool_name: LIST_LOGS, arguments: arguments,
                  present: ->(result) { Answers.read(result, PROVIDER) { |data| logs_result(result, resource, data, given, started, ended, limit) } })
      end

      def self.errors(resource, given, tool)
        limit = Answers.limit(given, ERROR_LIMIT)
        arguments = qstash(resource, tool)
        count = Answers.named(tool, COUNT)
        arguments[count] = limit if count
        started, ended = Answers.range(given)
        Route.new(tool_name: LIST_DLQ, arguments: arguments,
                  present: ->(result) { Answers.read(result, PROVIDER) { |data| errors_result(result, resource, data, given, started, ended) } })
      end

      # A workflow's runs in its region's QStash, newest first, or one run by its id with its steps. Only the workflow's
      # own runs are kept, by its address, which is also sent as a filter when the tool takes one.
      def self.history(resource, given, tool)
        url = resource.details.to_h[WORKFLOW_URL].presence
        raise Unroutable, "The address of workflow #{resource.name} is not known, so its runs cannot be read." unless url

        arguments = qstash(resource, tool)
        raise Unroutable, "Upstash's #{LIST_LOGS} takes no service here, so ask it for workflow runs with Upstash's own tool." unless arguments.key?(SERVICE)

        arguments[SERVICE] = WORKFLOW
        properties = Answers.properties(tool).to_h
        run = given["run"].to_s.strip.presence
        if run
          raise Unroutable, "Upstash's #{LIST_LOGS} takes no workflow run id here, so ask it with Upstash's own tool." unless properties.key?(WORKFLOW_RUN)

          arguments[WORKFLOW_RUN] = run
        elsif properties.key?(WORKFLOW_URL)
          # Only a page of this workflow's own runs is capped. Without the filter the region's runs crowd it, so the
          # tool's own page is read and the answer says so.
          arguments[WORKFLOW_URL] = url
          count = Answers.named(tool, COUNT)
          arguments[count] = RUNS_READ if count
        end
        crowded = run.nil? && !properties.key?(WORKFLOW_URL)
        Route.new(tool_name: LIST_LOGS, arguments: arguments,
                  present: ->(result) { Answers.read(result, PROVIDER) { |data| history_result(result, resource, url, data, given, run, crowded) } })
      end

      def self.history_result(result, resource, url, data, given, run, crowded)
        listed = listed(data, "runs")
        return nil unless listed

        runs = listed.select { |each| each["workflowUrl"] == url && each["workflowRunId"].present? }.map { |each| run_of(each, parts: run.present?) }
        answer = History.result(runs, what: "workflow #{resource.name}", name: (given["name"] unless run), limit: Answers.limit(given, History::LIMIT))
        note = ("Upstash's #{LIST_LOGS} here cannot filter by workflow, so these are this workflow's runs among the region's latest #{listed.size}, " \
                "and runs of other workflows may have crowded out older ones." if crowded)
        content = answer["content"] + [ ({ "type" => "text", "text" => note } if note) ].compact
        answer.merge("content" => content + Array(result["content"]).select { |part| Telemetry.link_line?(part["text"]) })
      end

      def self.run_of(run, parts:)
        status = History.status(run["workflowState"], RUN_STATUSES)
        answered = run.dig("failureFunction", "failStatus") if run["failureFunction"].is_a?(Hash)
        detail = [ ("answered #{answered}" if answered), ("in the dead letter queue as #{run['dlqId']}" if run["dlqId"].present?) ].compact.join(", ")
        History::Run.new(id: run["workflowRunId"], name: run["workflowUrl"], status: status, started_at: Answers.time_of(run["workflowRunCreatedAt"]),
                         finished_at: (Answers.time_of(run["workflowRunCompletedAt"]) if History::FINISHED.include?(status)), detail: detail.presence,
                         parts: (steps_of(run) if parts))
      end

      # A run's steps, in the groups Upstash ran them in, each with how it stands and, when it failed, the status its call answered.
      def self.steps_of(run)
        Array(run["steps"]).select { |group| group.is_a?(Hash) }.flat_map { |group| Array(group["steps"]) }.select { |step| step.is_a?(Hash) }.map do |step|
          status = History.status(step["state"], RUN_STATUSES)
          answered = step["callResponseStatus"]
          History::Part.new(id: (step["stepId"] || step["messageId"]).to_s, name: step["stepName"].presence || step["stepType"].to_s, status: status,
                            started_at: Answers.time_of(step["createdAt"]), detail: ("answered #{answered}" if answered && status == History::FAILED))
        end
      end

      def self.box(resource, tool)
        name = Answers.named(tool, BOX)
        raise Unroutable, "Upstash's #{tool.name} takes the box in a way Firefight does not know yet, so ask it with Upstash's own tool." unless name

        { name => resource.external_id }
      end

      # What the box printed, filtered by time and text here, since Upstash does not publish the filters box_logs takes.
      def self.box_logs(resource, given, tool)
        raise Unroutable, "A Box keeps what it prints, so stream must be #{STREAM_APP}." unless given["stream"].in?([ nil, "", STREAM_APP ])
        raise Unroutable, "Box logs are searched by text, not by a regular expression. Give text instead." if given["regex"].present?

        limit = Answers.limit(given, BOX_LOG_MOST, default: LOG_LIMIT)
        arguments = box(resource, tool)
        count = Answers.named(tool, %w[limit count])
        arguments[count] = BOX_LOG_MOST if count
        started, ended = Answers.range(given)
        Route.new(tool_name: BOX_LOGS, arguments: arguments,
                  present: ->(result) { Answers.read(result, PROVIDER) { |data| box_logs_result(result, resource, data, given, started, ended, limit) } })
      end

      def self.box_logs_result(result, resource, data, given, started, ended, limit)
        entries = listed(data, "logs")
        return nil unless entries

        lines = entries.filter_map do |entry|
          at = Answers.time_of(entry["timestamp"])
          text = [ entry["level"], entry["message"] ].compact_blank.join(" ")
          Telemetry::LogLine.new(at: at, source: entry["source"].presence || resource.name, text: text) if at&.between?(started, ended) && kept?(text, given)
        end.sort_by(&:at).reverse.first(limit)
        Answers.presented(result, Telemetry.logs_text(lines, asked: "Box #{resource.name}", limit: limit))
      end

      # A box's CPU, memory and disk over time. Upstash documents the action and not its answer, so it is not drawn.
      def self.box_metrics(resource, given, tool)
        metric_names(given, BOX_METRIC_NAMES.index_with(&:itself), "A Box")
        unless Array(Answers.properties(tool).to_h.dig(ACTION, "enum")).include?(BOX_HISTORY)
          raise Unroutable, "Upstash's #{BOX_METRICS} offers no #{BOX_HISTORY} action here, so ask it with Upstash's own tool."
        end

        Route.new(tool_name: BOX_METRICS, arguments: box(resource, tool).merge(ACTION => BOX_HISTORY))
      end

      # The object that holds what was asked, at the top of the answer or one level down.
      def self.holding(data, keys)
        return data if data.is_a?(Hash) && keys.any? { |key| data.key?(key) }
        return nil unless data.is_a?(Hash)

        data.values.find { |value| value.is_a?(Hash) && keys.any? { |key| value.key?(key) } }
      end

      def self.listed(data, key)
        return data if data.is_a?(Array) && data.all?(Hash)

        found = holding(data, [ key ])
        found && found[key].is_a?(Array) ? found[key] : nil
      end

      def self.metrics_result(result, resource, data, names, started, ended)
        stats = holding(data, names.map { |name| METRICS_READ.fetch(name).field })
        return nil unless stats

        charts = names.map do |name|
          metric = METRICS_READ.fetch(name)
          points = Array(stats[metric.field]).filter_map do |point|
            at = point.is_a?(Hash) && Telemetry.parse_time(point["x"])
            [ at, point["y"].to_f * metric.scale ] if at && !point["y"].nil? && at.between?(started, ended)
          end
          Telemetry::Chart.new(title: "#{metric.title} of #{resource.name}", unit: metric.unit,
                               series: [ Telemetry::Series.new(label: resource.name, points: points.sort_by(&:first)) ], from: started, to: ended,
                               link: Answers.linked(result))
        end
        Answers.presented(result, Telemetry.charts_text(charts), charts: charts)
      end

      def self.logs_result(result, resource, data, given, started, ended, limit)
        entries = listed(data, "logs")
        return nil unless entries

        lines = entries.filter_map do |entry|
          at = Answers.time_of(entry["time"])
          next unless at&.between?(started, ended)

          text = [ entry["state"], entry["url"], ("status #{entry['responseStatus']}" if entry["responseStatus"]), entry["error"].presence,
                   ("message #{entry['messageId']}" if entry["messageId"]) ].compact.join(", ")
          Telemetry::LogLine.new(at: at, source: entry["queueName"].presence || entry["scheduleId"].presence || "qstash", text: text) if kept?(text, given)
        end.sort_by(&:at).reverse.first(limit)
        Answers.presented(result, Telemetry.logs_text(lines, asked: "#{resource.name} deliveries", limit: limit))
      end

      # Messages that used up their retries, grouped by where they went and what came back.
      def self.errors_result(result, resource, data, given, started, ended)
        messages = listed(data, "messages")
        return nil unless messages

        failed = messages.select do |message|
          at = Answers.time_of(message["createdAt"])
          (at.nil? || at.between?(started, ended)) && kept?("#{message['url']} #{message['responseStatus']}", given.slice("text"))
        end
        return Answers.presented(result, "Nothing from #{resource.name} reached the dead letter queue in that range.") if failed.empty?

        groups = failed.group_by { |message| [ message["url"], message["responseStatus"] ] }.sort_by { |_, members| -members.size }
        lines = groups.map do |(url, status), members|
          newest = members.filter_map { |message| Answers.time_of(message["createdAt"]) }.max
          "#{url}, last answered #{status || 'nothing'}: #{members.size} messages, newest #{newest&.iso8601 || 'unknown'}, such as #{members.first['messageId']}"
        end
        Answers.presented(result, "Messages in #{resource.name}'s dead letter queue, by destination and answer, most first.\n#{lines.join("\n")}")
      end

      def self.kept?(text, given)
        return false if given["text"].present? && !text.include?(given["text"].to_s)

        given["exclude"].blank? || !text.include?(given["exclude"].to_s)
      end

      private_class_method :database, :qstash, :metrics, :period_for, :logs, :errors, :holding, :listed, :metrics_result,
                           :logs_result, :errors_result, :kept?, :box_route, :history, :history_result, :run_of, :steps_of, :box,
                           :box_logs, :box_logs_result, :box_metrics
    end
  end
end
