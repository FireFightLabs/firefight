module Integrations
  module Capabilities
    # Grafana watches what other connections run, so it answers logs from Loki, cpu and memory from Prometheus and
    # traces from Tempo for a resource on the map, by the resource's name. It answers through the tools of Grafana's
    # MCP server, whose names, arguments and answers are from grafana/mcp-grafana (tools/loki.go, tools/prometheus.go,
    # tools/tempo.go). The datasource each read goes to is the one the health check found (HealthProbes::Grafana).
    module Grafana
      extend Adapter

      PROVIDER_KEY = "grafana".freeze
      NAME = "Grafana".freeze
      WATCHED = Adapter::APP_KINDS
      SUPPORTS = {}.freeze
      OBSERVES = { LOGS => WATCHED, METRICS => WATCHED, TRACES => WATCHED }.freeze
      TOOLS = { LOGS => "query_loki_logs", METRICS => "query_prometheus", TRACES => "search_tempo_traces" }.freeze
      # Grafana's tools reach every stream, series and trace its datasources hold, far beyond the map, so they stay offered.
      WRAPPED = [].freeze
      SOURCES = { LOGS => HealthProbes::Grafana::LOKI, METRICS => HealthProbes::Grafana::PROMETHEUS, TRACES => HealthProbes::Grafana::TEMPO }.freeze
      SOURCE_NAMES = { LOGS => "Loki", METRICS => "Prometheus", TRACES => "Tempo" }.freeze

      # Loki puts a service_name label on every stream, from the labels a log shipper sets (Loki's get-started/labels).
      SERVICE_LABEL = "service_name".freeze
      # Tempo keeps the OpenTelemetry resource attribute service.name on every span.
      TRACE_SERVICE = "resource.service.name".freeze
      # The kubelet's cAdvisor metrics, documented by cAdvisor (docs/storage/prometheus.md) and labelled by Kubernetes with
      # the container's name. Network counters are kept per pod with no container label, so they cannot be read by name,
      # and other metrics depend on how each team instruments its code, so the platform answers them.
      METRIC_QUERIES = {
        "cpu" => "sum by (%<by>s) (rate(container_cpu_usage_seconds_total{%<selector>s}[%<window>s]))",
        "memory" => "sum by (%<by>s) (container_memory_working_set_bytes{%<selector>s}) / 1048576"
      }.freeze
      POD_LABEL = "pod".freeze
      METRIC_TITLES = { "cpu" => "CPU", "memory" => "Memory working set" }.freeze
      METRIC_UNITS = { "cpu" => "cores", "memory" => "MiB" }.freeze
      CONTAINER_LABEL = "container".freeze
      # Every metric asked goes in one query, each series labelled with the metric it is, so one call answers them all.
      METRIC_LABEL = "firefight_metric".freeze

      # query_loki_logs returns at most 100 lines unless the server is set up for more, and Tempo 20 traces a search.
      LOG_LIMIT = 100
      TRACE_LIMIT = 20
      POINTS = 60
      MIN_STEP = 15
      MIN_RATE_WINDOW = 300
      NOW = "now".freeze

      DATASOURCE_ARG = HealthProbes::Grafana::DATASOURCE_ARG

      # A stream other than what the app printed is the platform's to answer, and so is any metric but cpu and memory.
      def self.accepts?(key, given, settings: nil)
        case key
        when METRICS
          names = Array(given["metrics"]).map(&:to_s)
          names.any? && (names - METRIC_QUERIES.keys).empty?
        when LOGS then given["stream"].in?([ nil, "", STREAM_APP ])
        else true
        end
      end

      # Why it would not take what was asked, or nil.
      def self.refusal(key, resource, given)
        return if accepts?(key, given)
        return "Grafana answers only #{METRIC_QUERIES.keys.join(' and ')}, read from Prometheus. Ask the platform that runs #{resource.name} for the rest." if key == METRICS

        "Grafana holds what an app logs, so stream must be #{STREAM_APP}. Ask the platform that runs #{resource.name} for the rest."
      end

      # A connection answers only once its health check found the one datasource each read goes to.
      def self.reaches?(settings, key) = HealthProbes::Grafana.datasource(settings, SOURCES.fetch(key)).present?

      def self.route(key, resource, given, tool:, settings: nil)
        refused = refusal(key, resource, given)
        raise Unroutable, refused if refused

        source = HealthProbes::Grafana.datasource(settings, SOURCES.fetch(key))
        unless source
          raise Unroutable, "Grafana's #{SOURCE_NAMES.fetch(key)} datasource for this connection is not known. Its health check finds it once " \
                            "list_datasources is switched on. When Grafana has several, choose one on the connection's details in Integrations."
        end

        case key
        when LOGS then logs(resource, given, source, tool)
        when METRICS then metrics(resource, given, source, tool)
        when TRACES then traces(resource, given, source, tool)
        end
      end

      def self.logs(resource, given, source, tool)
        query = "{#{SERVICE_LABEL}=#{quoted(resource.name)}}"
        query += " |= #{quoted(given['text'])}" if given["text"].present?
        query += " != #{quoted(given['exclude'])}" if given["exclude"].present?
        query += " |~ #{quoted(given['regex'])}" if given["regex"].present?
        limit = Answers.limit(given, LOG_LIMIT)
        start, finish = times(given)
        arguments = { DATASOURCE_ARG => source["uid"], "logql" => query, "startRfc3339" => start, "endRfc3339" => finish,
                      "limit" => limit, "direction" => "backward" }
        Route.new(tool_name: TOOLS.fetch(LOGS), arguments: Answers.known!(tool, arguments, NAME),
                  present: ->(result) { Answers.read(result, PROVIDER_KEY) { |body| logs_result(resource, body, limit, result) } })
      end

      def self.metrics(resource, given, source, tool)
        names = Array(given["metrics"]).map(&:to_s).uniq
        started, ended = Answers.range(given)
        step = [ ((ended - started) / POINTS).ceil, MIN_STEP ].max
        selector = "#{CONTAINER_LABEL}=#{quoted(resource.name)}"
        expression = names.map do |name|
          labelled(name, format(METRIC_QUERIES.fetch(name), by: POD_LABEL, selector: selector, window: "#{[ step, MIN_RATE_WINDOW ].max}s"))
        end.join(" or ")
        start, finish = times(given)
        arguments = { DATASOURCE_ARG => source["uid"], "expr" => expression, "startTime" => start, "endTime" => finish,
                      "stepSeconds" => step, "queryType" => "range" }
        Route.new(tool_name: TOOLS.fetch(METRICS), arguments: Answers.known!(tool, arguments, NAME),
                  present: ->(result) { Answers.read(result, PROVIDER_KEY) { |body| metrics_result(resource, body, names, started, ended, result) } })
      end

      def self.traces(resource, given, source, tool)
        filters = [ "#{TRACE_SERVICE} = #{quoted(resource.name)}" ]
        filters << "name =~ #{quoted(".*#{regex_escaped(given['text'])}.*")}" if given["text"].present?
        limit = Answers.limit(given, TRACE_LIMIT)
        start, finish = times(given)
        arguments = { DATASOURCE_ARG => source["uid"], "query" => "{ #{filters.join(' && ')} }", "start" => start, "end" => finish }
        Route.new(tool_name: TOOLS.fetch(TRACES), arguments: Answers.known!(tool, arguments, NAME),
                  present: ->(result) { Answers.read(result, PROVIDER_KEY) { |body| traces_result(resource, body, limit, result) } })
      end

      # Minutes alone are sent as Grafana's relative time (now-15m to now), so the same request reads the same each time and
      # an approved call matches its retry. A start or end is sent in RFC 3339. Every tool here takes both.
      def self.times(given)
        minutes = Answers.minutes(given)
        return [ "#{NOW}-#{minutes}m", NOW ] if minutes

        Answers.range(given).map { |time| time.utc.iso8601 }
      end

      def self.logs_result(resource, body, limit, result)
        lines = Array(body["data"]).filter_map do |entry|
          at = Answers.time_of(entry["timestamp"])
          labels = entry["labels"].to_h
          Telemetry::LogLine.new(at: at, source: labels.values_at(POD_LABEL, "instance", CONTAINER_LABEL).compact.first || resource.name, text: entry["line"]) if at && entry["line"]
        end
        return if lines.empty?

        Answers.presented(result, Telemetry.logs_text(lines.sort_by(&:at).reverse, asked: "#{resource.name} in Loki", limit: limit))
      end

      def self.metrics_result(resource, body, names, started, ended, result)
        streams = Array(body["data"]).select { |stream| stream.is_a?(Hash) && stream["values"].is_a?(Array) }
        return if streams.empty?

        link = Answers.linked(result)
        charts = names.map do |name|
          series = streams.select { |stream| stream.dig("metric", METRIC_LABEL) == name }.map do |stream|
            points = stream["values"].filter_map { |at, value| [ Time.zone.at(at.to_f).utc, Float(value, exception: false) ] if at && Float(value, exception: false) }
            Telemetry::Series.new(label: stream.dig("metric", POD_LABEL).presence || resource.name, points: points)
          end
          Telemetry::Chart.new(title: "#{METRIC_TITLES.fetch(name)} of #{resource.name}", unit: METRIC_UNITS.fetch(name), series: series,
                               from: started, to: ended, link: link)
        end
        Answers.presented(result, "#{Telemetry.charts_text(charts)}\nRead from the #{CONTAINER_LABEL} label of Kubernetes' cAdvisor metrics.", charts: charts)
      end

      def self.traces_result(resource, body, limit, result)
        traces = Array(body["traces"]).select { |trace| trace.is_a?(Hash) && trace["traceID"].present? }
        return if traces.empty?

        shown = traces.sort_by { |trace| -trace["durationMs"].to_f }.first(limit).map do |trace|
          matched = Array(trace["spanSets"] || [ trace["spanSet"] ].compact).sum { |set| set["matched"].to_i }
          [ Answers.time_of(trace["startTimeUnixNano"])&.iso8601, "trace #{trace['traceID']}", trace["rootServiceName"], trace["rootTraceName"],
            "#{trace['durationMs'].to_i} ms", ("#{matched} matching spans" if matched.positive?) ].compact.join(", ")
        end
        cut = traces.size >= TRACE_LIMIT ? " Tempo answers the first #{TRACE_LIMIT} it finds, not every one, so narrow the range or the text to see others." : ""
        Answers.presented(result, "#{shown.size} traces through #{resource.name} in Tempo, slowest first.#{cut} Grafana's get_tempo_trace shows " \
                          "where the time in one went.\n#{shown.join("\n")}")
      end

      # One metric's series, labelled with the metric they are, so several can share a query.
      def self.labelled(name, query) = "label_replace(#{query}, #{quoted(METRIC_LABEL)}, #{quoted(name)}, \"\", \"\")"

      # A string literal in LogQL, PromQL and TraceQL, which all read Go's escapes.
      def self.quoted(text) = "\"#{text.to_s.gsub('\\') { '\\\\' }.gsub('"', '\\"')}\""

      def self.regex_escaped(text) = text.to_s.gsub(/[\\.+*?()|\[\]{}^$]/) { |char| "\\#{char}" }

      private_class_method :refusal, :logs, :metrics, :traces, :times, :logs_result, :metrics_result, :traces_result, :regex_escaped
    end
  end
end
