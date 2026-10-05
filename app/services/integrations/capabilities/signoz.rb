module Integrations
  module Capabilities
    # SigNoz watches what other connections run, so it answers logs, traces, errors and request metrics for a resource on
    # the map by its OpenTelemetry service.name, which is the resource's name. It answers through the tools of SigNoz's
    # MCP server, whose names, arguments and answers are from SigNoz/signoz-mcp-server (internal/handler/tools/logs.go
    # and traces.go for the tools, pkg/timeutil/time.go for timeRange, pkg/querybuilder/logs_guide.go for the filter
    # syntax) and SigNoz's querybuildertypesv5 for the answer.
    module Signoz
      extend Adapter

      PROVIDER_KEY = "signoz".freeze
      NAME = "SigNoz".freeze
      WATCHED = Adapter::APP_KINDS
      SUPPORTS = {}.freeze
      OBSERVES = { LOGS => WATCHED, METRICS => WATCHED, TRACES => WATCHED, ERRORS => Adapter::ERROR_KINDS }.freeze
      AGGREGATE = "signoz_aggregate_traces".freeze
      TOOLS = { LOGS => "signoz_search_logs", METRICS => AGGREGATE, TRACES => "signoz_search_traces", ERRORS => AGGREGATE }.freeze
      # SigNoz's tools reach every service it sees, far beyond the map, so they stay offered as they are.
      WRAPPED = [].freeze

      # Requests and errors are counted from the service's spans, one series each for has_error true and false, so one
      # call answers both. Other metrics depend on what each team sends, so the platform answers them.
      METRIC_NAMES = %w[requests errors].freeze
      ERROR_FIELD = "has_error".freeze
      LOG_LIMIT = 200
      TRACE_LIMIT = 50
      ERROR_LIMIT = 50
      POINTS = 60
      MIN_STEP = 60

      # A stream other than what the app printed is the platform's, and so is any metric but requests and errors.
      def self.accepts?(key, given, settings: nil)
        case key
        when METRICS
          names = Array(given["metrics"]).map(&:to_s)
          names.any? && (names - METRIC_NAMES).empty?
        when LOGS then given["stream"].in?([ nil, "", STREAM_APP ])
        else true
        end
      end

      def self.route_refusal(key, resource, given, settings: nil)
        return if accepts?(key, given)
        return "SigNoz counts only #{METRIC_NAMES.join(' and ')} from a service's spans. Ask the platform that runs #{resource.name} for the rest." if key == METRICS

        "SigNoz holds what an app logs, so stream must be #{STREAM_APP}. Ask the platform that runs #{resource.name} for the rest."
      end

      def self.route(key, resource, given, tool:, settings: nil)
        refusal = route_refusal(key, resource, given)
        raise Unroutable, refusal if refusal

        case key
        when LOGS then logs(resource, given, tool)
        when METRICS then metrics(resource, given, tool)
        when TRACES then traces(resource, given, tool)
        when ERRORS then errors(resource, given, tool)
        end
      end

      def self.logs(resource, given, tool)
        limit = Answers.limit(given, LOG_LIMIT)
        filters = []
        filters << "body REGEXP #{quoted(given['regex'])}" if given["regex"].present?
        filters << "body NOT CONTAINS #{quoted(literal(given['exclude']))}" if given["exclude"].present?
        arguments = { "service" => resource.name, "limit" => limit, **times(given) }
        arguments["searchText"] = given["text"] if given["text"].present?
        arguments["filter"] = filters.join(" AND ") if filters.any?
        Route.new(tool_name: TOOLS.fetch(LOGS), arguments: Answers.known!(tool, arguments, NAME),
                  present: ->(result) { Answers.read(result, PROVIDER_KEY) { |body| logs_result(resource, body, limit, result) } })
      end

      def self.traces(resource, given, tool)
        limit = Answers.limit(given, TRACE_LIMIT)
        arguments = { "service" => resource.name, "limit" => limit, **times(given) }
        arguments["filter"] = "name CONTAINS #{quoted(literal(given['text']))}" if given["text"].present?
        Route.new(tool_name: TOOLS.fetch(TRACES), arguments: Answers.known!(tool, arguments, NAME),
                  present: ->(result) { Answers.read(result, PROVIDER_KEY) { |body| traces_result(resource, body, result) } })
      end

      def self.errors(resource, given, tool)
        arguments = { "aggregation" => "count", "service" => resource.name, "error" => true, "groupBy" => "name",
                      "requestType" => "scalar", "orderBy" => "count() desc", "limit" => Answers.limit(given, ERROR_LIMIT), **times(given) }
        arguments["filter"] = "status_message CONTAINS #{quoted(literal(given['text']))}" if given["text"].present?
        Route.new(tool_name: TOOLS.fetch(ERRORS), arguments: Answers.known!(tool, arguments, NAME),
                  present: ->(result) { Answers.read(result, PROVIDER_KEY) { |body| errors_result(resource, body, result) } })
      end

      def self.metrics(resource, given, tool)
        names = Array(given["metrics"]).map(&:to_s).uniq
        started, ended = Answers.range(given)
        step = [ ((ended - started) / POINTS).ceil, MIN_STEP ].max
        arguments = { "aggregation" => "count", "service" => resource.name, "groupBy" => ERROR_FIELD, "requestType" => "time_series",
                      "stepInterval" => step, **times(given) }
        Route.new(tool_name: TOOLS.fetch(METRICS), arguments: Answers.known!(tool, arguments, NAME),
                  present: ->(result) { Answers.read(result, PROVIDER_KEY) { |body| metrics_result(resource, body, names, step, started, ended, result) } })
      end

      # Minutes alone are sent as SigNoz's relative timeRange (60m), so the same request reads the same each time and an
      # approved call matches its retry. A start or end is sent as both, in Unix milliseconds, which override timeRange.
      def self.times(given)
        minutes = Answers.minutes(given)
        return { "timeRange" => "#{minutes}m" } if minutes

        started, ended = Answers.range(given)
        { "start" => (started.to_f * 1000).to_i, "end" => (ended.to_f * 1000).to_i }
      end

      # The rows of a raw answer: {"status", "data": {"type": "raw", "data": {"results": [{"rows": [...]}]}}}.
      def self.rows(body) = Array(body.dig("data", "data", "results")).flat_map { |each| Array(each["rows"]) }.select { |row| row.is_a?(Hash) }

      def self.logs_result(resource, body, limit, result)
        lines = rows(body).filter_map do |row|
          fields = row["data"].to_h
          at = Answers.time_of(row["timestamp"] || fields["timestamp"])
          text = fields["body"]
          Telemetry::LogLine.new(at: at, source: fields["severity_text"].presence || resource.name, text: text) if at && text
        end
        return if lines.empty?

        Answers.presented(result, Telemetry.logs_text(lines.sort_by(&:at).reverse, asked: "#{resource.name} in SigNoz", limit: limit))
      end

      def self.traces_result(resource, body, result)
        spans = rows(body).map { |row| row["data"].to_h.merge("webUrl" => row["webUrl"] || row.dig("data", "webUrl")) }.select { |span| span["trace_id"].present? }
        return if spans.empty?

        shown = spans.sort_by { |span| [ span[ERROR_FIELD] == true ? 0 : 1, -span["duration_nano"].to_f ] }.map do |span|
          [ "trace #{span['trace_id']}", span["name"], "#{(span['duration_nano'].to_f / 1_000_000).round(1)} ms",
            ("failed: #{span['status_message'].presence || 'error'}" if span[ERROR_FIELD] == true), span["webUrl"].presence ].compact.join(", ")
        end
        Answers.presented(result, "#{shown.size} spans of #{resource.name} in SigNoz, failed first, then slowest. signoz_get_trace_details " \
                                  "shows where the time in one trace went.\n#{shown.join("\n")}")
      end

      # A scalar answer: {"columns": [{"name"}...], "data": [[...]]}, the group first and its count last.
      def self.errors_result(resource, body, result)
        scalar = Array(body.dig("data", "data", "results")).find { |each| each.is_a?(Hash) && each["data"].is_a?(Array) }
        return unless scalar

        groups = scalar["data"].select { |row| row.is_a?(Array) && row.size >= 2 }
        return if groups.empty?

        shown = groups.map { |row| "#{row.first}: #{row.last.to_i} failed spans" }
        Answers.presented(result, "#{shown.size} kinds of failing operation in #{resource.name} in SigNoz, most frequent first. " \
                                  "signoz_search_traces with error true shows the spans of one.\n#{shown.join("\n")}")
      end

      # A time series answer holds aggregations whose series are labelled by has_error, each a list of timestamp and value in
      # Unix milliseconds. Counts per step become counts per minute.
      def self.metrics_result(resource, body, names, step, started, ended, result)
        series = Array(body.dig("data", "data", "results")).flat_map { |each| Array(each["aggregations"]) }.flat_map { |each| Array(each["series"]) }
        return if series.empty?

        per_minute = step / 60.0
        by_error = series.group_by { |each| Array(each["labels"]).find { |label| label.dig("key", "name") == ERROR_FIELD }&.fetch("value", nil).to_s == "true" }
        counted = ->(list) { list.flat_map { |each| Array(each["values"]) }.group_by { |point| point["timestamp"] }.map { |at, points| [ Answers.time_of(at), points.sum { |point| point["value"].to_f } / per_minute ] }.sort_by(&:first) }
        points = { "requests" => counted.call(series), "errors" => counted.call(by_error.fetch(true, [])) }
        link = Answers.linked(result)
        charts = names.map do |name|
          Telemetry::Chart.new(title: "#{name.capitalize} of #{resource.name}", unit: "per minute", series: [ Telemetry::Series.new(label: resource.name, points: points.fetch(name)) ],
                               from: started, to: ended, link: link)
        end
        Answers.presented(result, "#{Telemetry.charts_text(charts)}\nCounted from #{resource.name}'s spans in SigNoz, failed spans being errors.", charts: charts)
      end

      # A string in SigNoz's filter syntax, with backslashes doubled and apostrophes escaped, in single quotes.
      def self.quoted(text) = "'#{text.to_s.gsub('\\') { '\\\\' }.gsub("'") { "\\'" }}'"

      # Literal text for CONTAINS, where % and _ would otherwise match anything.
      def self.literal(text) = text.to_s.gsub(/[%_]/) { |char| "\\#{char}" }

      private_class_method :logs, :traces, :errors, :metrics, :times, :rows, :logs_result, :traces_result, :errors_result, :metrics_result, :literal
    end
  end
end
