module Integrations
  module Capabilities
    # Upstash answers through its remote MCP server at mcp.upstash.com. Upstash's docs, agent-resources/mcp, name the
    # server's tools and say every QStash tool takes a region and a service. They publish no other parameter, so the
    # arguments follow the parameters the connected tool reports, as for Datadog, and Firefight never sends one it does
    # not report. Answers are read as Upstash's Developer and QStash APIs document them in DatabaseStats, LogEntry and
    # DLQMessage, and filtered here by time and text where the tool takes no such filter. An answer in another shape
    # reaches the agent as it came. A Redis database answers status and metrics, and the QStash of a region answers its
    # delivery logs, and its dead letter queue as errors.
    module Upstash
      extend Adapter

      PROVIDER = "Upstash".freeze
      PROVIDER_KEY = "upstash".freeze
      GET_DATABASE = "redis_get_database".freeze
      GET_STATS = "redis_get_stats".freeze
      LIST_LOGS = "logs_list".freeze
      LIST_DLQ = "dlq_list".freeze
      SUPPORTS = {
        STATUS => [ ResourceMap::KIND_DATABASE ], METRICS => [ ResourceMap::KIND_DATABASE ],
        LOGS => [ ResourceMap::KIND_QUEUE ], ERRORS => [ ResourceMap::KIND_QUEUE ]
      }.freeze
      TOOLS = { STATUS => GET_DATABASE, METRICS => GET_STATS, LOGS => LIST_LOGS, ERRORS => LIST_DLQ }.freeze
      # Their arguments are read off the connected tools, so they stay offered for when they cannot be.
      WRAPPED = [].freeze
      DATABASE = %w[database_id id].freeze
      REGION = "region".freeze
      SERVICE = "service".freeze
      QSTASH = "qstash".freeze
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

      def self.route(key, resource, given, tool: nil, settings: nil)
        case key
        when STATUS then Route.new(tool_name: GET_DATABASE, arguments: database(resource, tool))
        when METRICS then metrics(resource, given, tool)
        when LOGS then logs(resource, given, tool)
        when ERRORS then errors(resource, given, tool)
        end
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
                           :logs_result, :errors_result, :kept?
    end
  end
end
