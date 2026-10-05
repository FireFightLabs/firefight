module Integrations
  module Capabilities
    # Datadog watches what other connections run, so it answers logs, metrics, traces and errors for a resource on the map by its
    # Datadog service, which is the resource's name. It answers through the tools its MCP server offers. The server
    # publishes each tool's parameters but Datadog's docs do not, so the arguments are written against the parameters
    # the connected server reports, and a parameter it does not have is never sent.
    module Datadog
      extend Adapter

      WATCHED = Adapter::APP_KINDS
      SUPPORTS = {}.freeze
      OBSERVES = { LOGS => WATCHED, METRICS => WATCHED, TRACES => WATCHED, ERRORS => Adapter::ERROR_KINDS }.freeze
      TOOLS = { LOGS => "search_datadog_logs", METRICS => "get_datadog_metric", TRACES => "search_datadog_spans",
                ERRORS => "search_datadog_error_tracking_issues" }.freeze
      # The container metrics Datadog documents under every service it tags (its Docker and containerd integrations).
      # The rest depend on how a team set Datadog up, so the platform answers them.
      METRIC_MAP = { "cpu" => "container.cpu.usage", "memory" => "container.memory.usage" }.freeze
      METRIC_NAME = "metric_name".freeze
      # Datadog's tools reach every service Datadog sees, far beyond the map, so they stay offered as they are.
      WRAPPED = [].freeze
      PROVIDER_KEY = "datadog".freeze

      # The names a Datadog tool may give each argument, in the order they are tried.
      START = %w[from start start_time from_time].freeze
      FINISH = %w[to end end_time to_time].freeze
      RANGE = %w[time_range timeframe].freeze
      LIMIT = %w[limit max_results page_size].freeze
      SERVICE = "service".freeze
      QUERY = "query".freeze
      NOW = "now".freeze

      # A regular expression, or a stream other than what the app printed, is the platform's to answer, and so is any
      # metric but one Datadog keeps the same way everywhere, asked alone, since its tool reads one metric a call.
      def self.accepts?(key, given, settings: nil)
        return Array(given["metrics"]).size == 1 && METRIC_MAP.key?(Array(given["metrics"]).first.to_s) if key == METRICS

        given["regex"].blank? && given["stream"].in?([ nil, "", STREAM_APP ])
      end

      def self.route(key, resource, given, tool:, settings: nil)
        return metric(resource, given, tool) if key == METRICS

        raise Unroutable, "Datadog searches by text, not by a regular expression. Give text instead." if given["regex"].present?
        unless accepts?(key, given)
          raise Unroutable, "Datadog holds what an app sends it, so stream must be #{STREAM_APP}. Ask the platform that runs #{resource.name} for the rest."
        end

        properties = tool.params_schema.to_h.fetch("properties", {})
        filter = [ *([ "service:#{resource.name}" ] unless properties.key?(SERVICE)), (quoted(given["text"]) if given["text"].present?),
                   ("-#{quoted(given['exclude'])}" if given["exclude"].present?) ].compact.join(" ")
        arguments = { QUERY => filter.presence || "*" }
        arguments[SERVICE] = resource.name if properties.key?(SERVICE)
        limit = given["limit"].to_i
        if limit.positive? && (name = LIMIT.find { |each| properties.key?(each) })
          arguments[name] = limit
        end
        Route.new(tool_name: TOOLS.fetch(key), arguments: arguments.merge(range(given, properties)))
      end

      # One metric of the service, averaged, as Datadog's metric query reads it.
      def self.metric(resource, given, tool)
        unless accepts?(METRICS, given)
          raise Unroutable, "Datadog answers one metric a call, and only #{METRIC_MAP.keys.join(' or ')}. Ask the platform that runs #{resource.name} for the rest."
        end

        name = METRIC_MAP.fetch(Array(given["metrics"]).first.to_s)
        properties = tool.params_schema.to_h.fetch("properties", {})
        arguments = {}
        arguments[METRIC_NAME] = name if properties.key?(METRIC_NAME)
        arguments[QUERY] = "avg:#{name}{service:#{resource.name}}" if properties.key?(QUERY)
        raise Unroutable, "Datadog's metric tool takes its metric in a way Firefight does not know yet, so ask it with Datadog's own tool." if arguments.empty?
        Route.new(tool_name: TOOLS.fetch(METRICS), arguments: arguments.merge(range(given, properties)))
      end

      # The time asked for, as the tool takes it: two top level fields, or one object holding them. Minutes alone are
      # sent as Datadog's relative time (now-15m), so the same request reads the same each time and an approved call
      # matches its retry. A start or end is sent in ISO 8601.
      def self.range(given, properties)
        holder = RANGE.find { |each| properties.key?(each) }
        fields = holder ? properties.dig(holder, "properties").to_h : properties
        start = START.find { |each| fields.key?(each) }
        finish = FINISH.find { |each| fields.key?(each) }
        unless start && finish && [ start, finish ].all? { |name| fields[name].to_h.fetch("type", "string") == "string" }
          raise Unroutable, "Datadog's tool takes its time range in a way Firefight does not know yet, so ask it with Datadog's own tool."
        end

        holder ? { holder => times(given, start, finish) } : times(given, start, finish)
      end

      def self.times(given, start, finish)
        if given["start"].blank? && given["end"].blank?
          minutes = [ given["minutes"].to_i.positive? ? given["minutes"].to_i : DEFAULT_MINUTES, MAX_MINUTES ].min
          return { start => "#{NOW}-#{minutes}m", finish => NOW }
        end

        started, ended = Telemetry.range(given, default_minutes: DEFAULT_MINUTES, max_minutes: MAX_MINUTES)
        { start => started.utc.iso8601, finish => ended.utc.iso8601 }
      end

      def self.quoted(text) = "\"#{text.to_s.delete('"')}\""
      private_class_method :metric, :range, :times, :quoted
    end
  end
end
