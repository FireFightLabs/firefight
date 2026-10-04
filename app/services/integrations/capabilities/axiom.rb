module Integrations
  module Capabilities
    # Axiom watches what other connections run, so it answers logs from the connection's logs dataset, and traces,
    # errors and request counts from its traces dataset, for a resource on the map by its OpenTelemetry service.name,
    # which is the resource's name. Every answer is one APL query through queryDataset, the query tool of Axiom's hosted
    # MCP server (axiomhq/docs, console/intelligence/mcp-server/tools.mdx). Axiom publishes that tool's parameters only
    # from its server, so the query and time arguments are written against the ones the connected tool reports. The
    # trace fields (service.name, name, duration, error, status.message, trace_id, parent_span_id) are from Axiom's
    # traces reference (query-data/traces.mdx), and relative times such as now-1h from its API reference.
    module Axiom
      extend Adapter

      PROVIDER_KEY = "axiom".freeze
      NAME = "Axiom".freeze
      WATCHED = Adapter::APP_KINDS
      SUPPORTS = {}.freeze
      OBSERVES = { LOGS => WATCHED, METRICS => WATCHED, TRACES => WATCHED, ERRORS => Adapter::ERROR_KINDS }.freeze
      # Firefight names a tool in lower case (McpExecutor.tool_definitions), so queryDataset is querydataset here.
      QUERY_DATASET = "querydataset".freeze
      TOOLS = { LOGS => QUERY_DATASET, METRICS => QUERY_DATASET, TRACES => QUERY_DATASET, ERRORS => QUERY_DATASET }.freeze
      # queryDataset reads every dataset Axiom holds, far beyond the map, so it stays offered as it is.
      WRAPPED = [].freeze
      # The datasets a connection reads, which the connect form asks for. Traces are optional.
      LOGS_DATASET = "logs_dataset".freeze
      TRACES_DATASET = "traces_dataset".freeze
      DATASETS = { LOGS => LOGS_DATASET, METRICS => TRACES_DATASET, TRACES => TRACES_DATASET, ERRORS => TRACES_DATASET }.freeze
      # An Axiom dataset name is 1 to 128 letters, digits and dashes (axiomhq/docs, reference/datasets.mdx), as the connect
      # form checks, so it goes into ['name'] as it is.
      DATASET_NAME = /\A[A-Za-z0-9-]{1,128}\z/
      # The names queryDataset may give each argument, in the order they are tried.
      QUERY = %w[apl query].freeze
      START = %w[startTime start_time start].freeze
      FINISH = %w[endTime end_time end].freeze
      METRIC_NAMES = %w[requests errors].freeze
      LOG_LIMIT = 200
      TRACE_LIMIT = 50
      ERROR_LIMIT = 50
      POINTS = 60
      MIN_STEP = 60

      def self.dataset(settings, key)
        name = settings&.field(DATASETS.fetch(key)).to_s.strip
        name if name.match?(DATASET_NAME)
      end

      # A connection answers only for what it has a dataset for.
      def self.reaches?(settings, key) = dataset(settings, key).present?

      # Logs are searched by text, as Axiom's search operator does. A regular expression, text to leave out or a stream
      # other than what the app printed are for another connection, and so is any metric but requests and errors.
      def self.accepts?(key, given, settings: nil)
        case key
        when METRICS
          names = Array(given["metrics"]).map(&:to_s)
          names.any? && (names - METRIC_NAMES).empty?
        when LOGS then given["regex"].blank? && given["exclude"].blank? && given["stream"].in?([ nil, "", STREAM_APP ])
        else true
        end
      end

      def self.route_refusal(key, resource, given, settings: nil)
        return if accepts?(key, given)
        return "Axiom counts only #{METRIC_NAMES.join(' and ')} from #{resource.name}'s traces. Ask the platform that runs it for the rest." if key == METRICS
        return "Axiom holds what an app sends it, so stream must be #{STREAM_APP}. Ask the platform that runs #{resource.name} for the rest." if given["stream"].present? && given["stream"] != STREAM_APP

        "Firefight searches Axiom by text. For a regular expression or text to leave out, write the APL with #{QUERY_DATASET}."
      end

      def self.route(key, resource, given, tool:, settings: nil)
        refusal = route_refusal(key, resource, given)
        raise Unroutable, refusal if refusal

        source = dataset(settings, key)
        unless source
          which = DATASETS.fetch(key) == LOGS_DATASET ? "logs" : "traces"
          raise Unroutable, "This Axiom connection does not name a #{which} dataset. Connect it again and name the dataset that holds them."
        end

        apl = case key
        when LOGS then logs(resource, given, source)
        when TRACES then traces(resource, given, source)
        when ERRORS then errors(resource, given, source)
        when METRICS then metrics(resource, given, source)
        end
        Route.new(tool_name: QUERY_DATASET, arguments: arguments(tool, apl, given))
      end

      def self.logs(resource, given, source)
        apl = "['#{source}'] | where ['service.name'] == #{quoted(resource.name)}"
        apl += " | search #{quoted(given['text'])}" if given["text"].present?
        "#{apl} | sort by _time desc | take #{Answers.limit(given, LOG_LIMIT)}"
      end

      def self.traces(resource, given, source)
        apl = "['#{source}'] | where ['service.name'] == #{quoted(resource.name)}"
        apl += " | where name contains #{quoted(given['text'])}" if given["text"].present?
        "#{apl} | sort by error desc, duration desc | take #{Answers.limit(given, TRACE_LIMIT)} " \
          "| project _time, trace_id, name, duration, error, ['status.message']"
      end

      def self.errors(resource, given, source)
        apl = "['#{source}'] | where ['service.name'] == #{quoted(resource.name)} and error == true"
        apl += " | where ['status.message'] contains #{quoted(given['text'])}" if given["text"].present?
        "#{apl} | summarize count(), first_seen = min(_time), last_seen = max(_time) by name, ['status.message'] " \
          "| sort by last_seen desc | take #{Answers.limit(given, ERROR_LIMIT)}"
      end

      # Requests are root spans, as Axiom's traces reference counts them, by minute bucket and whether they failed.
      def self.metrics(resource, given, source)
        started, ended = Answers.range(given)
        step = [ ((ended - started) / POINTS).ceil, MIN_STEP ].max
        "['#{source}'] | where ['service.name'] == #{quoted(resource.name)} and isnull(parent_span_id) " \
          "| summarize count() by bin(_time, #{step}s), error | sort by _time asc"
      end

      # The query and the time asked, as the connected tool takes them. Minutes alone are sent as Axiom's relative time
      # (now-60m to now), so the same request reads the same each time and an approved call matches its retry. A start
      # or end is sent in ISO 8601. A tool that takes no time arguments gets the range in the APL itself.
      def self.arguments(tool, apl, given)
        query = Answers.named(tool, QUERY)
        raise Unroutable, "Axiom's queryDataset takes its query in a way Firefight does not know, so ask it with Axiom's own tools." unless query

        minutes = Answers.minutes(given)
        started, ended = Answers.range(given)
        start, finish = Answers.named(tool, START), Answers.named(tool, FINISH)
        return { query => "#{apl.sub(' | ', " | where _time between (#{between(minutes, started, ended)}) | ")}" } unless start && finish

        { query => apl, start => minutes ? "now-#{minutes}m" : started.utc.iso8601, finish => minutes ? "now" : ended.utc.iso8601 }
      end

      def self.between(minutes, started, ended)
        minutes ? "ago(#{minutes}m) .. now()" : "datetime(#{started.utc.iso8601}) .. datetime(#{ended.utc.iso8601})"
      end

      # A string literal in APL, which reads JSON's escapes.
      def self.quoted(text) = text.to_s.to_json

      private_class_method :logs, :traces, :errors, :metrics, :arguments, :between
    end
  end
end
