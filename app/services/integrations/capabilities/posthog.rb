module Integrations
  module Capabilities
    # PostHog keeps the logs and traces a team sends it over OpenTelemetry, by service name, so it answers logs and
    # traces for a resource on the map by the resource's name. The arguments follow the tools' published schemas in
    # PostHog/posthog, services/mcp. query-logs takes LogsQueryCreateBody (src/generated/logs/api.ts) and
    # query-apm-spans takes TracingSpansQueryCreateBody (src/generated/tracing/api.ts), every field inside query. Its
    # errors are grouped by fingerprint, release and URL, never by service, so they are not routed here.
    module Posthog
      extend Adapter

      WATCHED = Adapter::APP_KINDS
      SUPPORTS = {}.freeze
      OBSERVES = { LOGS => WATCHED, TRACES => WATCHED }.freeze
      TOOLS = { LOGS => "query_logs", TRACES => "query_apm_spans" }.freeze
      # PostHog's tools reach every service it holds logs or traces for, far beyond the map, so they stay offered.
      WRAPPED = [].freeze
      PROVIDER_NAME = "PostHog".freeze

      QUERY = "query".freeze
      MAX_LIMIT = 1000
      # Log filters on the body are type log, key message. Span filters on the operation are type span, key name.
      LOG_FILTER = { "type" => "log", "key" => "message" }.freeze
      SPAN_FILTER = { "type" => "span", "key" => "name" }.freeze
      # How a list with nothing in it reads in the TOON text the server answers with (src/lib/response.ts), before any
      # hint the server adds after a blank line (src/lib/discovery-hints.ts).
      EMPTY = "results: []".freeze

      # PostHog holds what the app sends it, so a build, request or other stream is the platform's to answer.
      def self.accepts?(key, given, settings: nil) = key != LOGS || given["stream"].in?([ nil, "", STREAM_APP ])

      def self.route(key, resource, given, tool:, settings: nil)
        unless accepts?(key, given)
          raise Unroutable, "PostHog holds the logs an app sends it, so stream must be #{STREAM_APP}. Ask the platform that runs #{resource.name} for the rest."
        end

        query = key == LOGS ? logs(given) : traces(given)
        query["serviceNames"] = [ resource.name ]
        query["dateRange"] = date_range(given)
        query["limit"] = Answers.limit(given, MAX_LIMIT) if given["limit"].to_i.positive?
        arguments = { QUERY => query }
        Answers.known!(tool, arguments, PROVIDER_NAME) if tool
        Route.new(tool_name: TOOLS.fetch(key), arguments: arguments, present: method(:present))
      end

      # Newest first, with the text, regular expression and words to leave out as filters on the log body.
      def self.logs(given)
        filters = [ ([ "icontains", given["text"] ] if given["text"].present?), ([ "regex", given["regex"] ] if given["regex"].present?),
                    ([ "not_icontains", given["exclude"] ] if given["exclude"].present?) ].compact
        { "orderBy" => "latest", "filterGroup" => filters.map { |operator, value| LOG_FILTER.merge("operator" => operator, "value" => value.to_s) } }
      end

      # The service's own spans, root or not, slowest first. PostHog collapses results to root spans unless told
      # otherwise, which would hide a service that is called by another (products/tracing/mcp/prompts/query-apm-spans.md).
      def self.traces(given)
        filters = given["text"].present? ? [ SPAN_FILTER.merge("operator" => "icontains", "value" => given["text"].to_s) ] : []
        { "orderBy" => "duration", "orderDirection" => "DESC", "flatSpans" => true, "rootSpans" => false, "filterGroup" => filters }
      end

      # Minutes alone are sent as PostHog's relative time (-1h, or -15M for minutes, posthog/utils.py
      # get_delta_mapping_for), so the same request reads the same each time and an approved call matches its retry. A
      # start or end is sent in ISO 8601.
      def self.date_range(given)
        minutes = Answers.minutes(given)
        return { "date_from" => (minutes % 60).zero? ? "-#{minutes / 60}h" : "-#{minutes}M" } if minutes

        started, ended = Answers.range(given)
        { "date_from" => started.utc.iso8601, "date_to" => ended.utc.iso8601 }
      end

      # An empty list reads as nothing in JSON, so the platform is asked instead. PostHog's own hint after an empty log
      # search points at skills Halon does not have, so it goes with it.
      def self.present(result)
        parts = Array(result["content"])
        empty = parts.any? && parts.all? do |part|
          text = part["text"].to_s
          Telemetry.link_line?(text) || text.split("\n\n").first.to_s.strip == EMPTY
        end
        return result unless empty && !result["isError"]

        result.merge("content" => parts.map { |part| Telemetry.link_line?(part["text"]) ? part : part.merge("text" => { "results" => [] }.to_json) })
      end
      private_class_method :logs, :traces, :date_range, :present
    end
  end
end
