module Integrations
  module SourceLinks
    # A Loki, Prometheus or Tempo query through Grafana's MCP server, or a trace by its id, links to Grafana's Explore on
    # the same query over the same time, at the address the connection's health probe learned (HealthProbes::Grafana).
    # The link is the form Grafana documents for opening Explore from another tool ("Generate Explore URLs from external
    # tools"), with panes as JSON and schemaVersion 1. A pane names its datasource, its queries and its range in
    # milliseconds. Each query carries its datasource's own fields, expr for Loki and Prometheus, and query with queryType
    # traceql for Tempo (grafana-tempo-datasource, src/dataquery.ts). Without the address there is no link.
    class Grafana
      NAME = "Grafana".freeze
      Query = Data.define(:query, :start, :finish, :model)
      TOOLS = Capabilities::Grafana::TOOLS
      LOGQL = Query.new(query: "logql", start: "startRfc3339", finish: "endRfc3339", model: ->(text) { { "expr" => text } })
      # Tempo's query field takes a TraceQL query or a trace id alike.
      TRACEQL = ->(text) { { "queryType" => "traceql", "query" => text } }
      QUERIES = {
        TOOLS.fetch(Capabilities::LOGS) => LOGQL, "query_loki_patterns" => LOGQL, "query_loki_stats" => LOGQL,
        TOOLS.fetch(Capabilities::METRICS) => Query.new(query: "expr", start: "startTime", finish: "endTime", model: ->(text) { { "expr" => text } }),
        TOOLS.fetch(Capabilities::TRACES) => Query.new(query: "query", start: "start", finish: "end", model: TRACEQL),
        "get_tempo_trace" => Query.new(query: "trace_id", start: nil, finish: nil, model: TRACEQL)
      }.freeze
      SCHEMA_VERSION = 1
      PANE = "a".freeze
      # Every tool here reads the last hour when it is given no time.
      DEFAULT_FROM = "now-1h".freeze
      RELATIVE = /\Anow(?:-(?<amount>\d+)(?<unit>s|m|h|d|w))?\z/
      UNITS = { "s" => 1.second, "m" => 1.minute, "h" => 1.hour, "d" => 1.day, "w" => 1.week }.freeze

      def initialize(settings)
        @settings = settings
      end

      def link(tool_name:, arguments:, text: "")
        known = QUERIES[tool_name]
        address = HealthProbes::Grafana.address(@settings)
        asked = arguments.to_h.stringify_keys
        uid = asked[HealthProbes::Grafana::DATASOURCE_ARG].presence
        query = asked[known.query].presence if known
        return unless address && uid && query

        from = millis((asked[known.start] if known.start).presence || DEFAULT_FROM)
        to = millis((asked[known.finish] if known.finish).presence || "now")
        return unless from && to

        source = { "uid" => uid, "type" => type_of(uid) }.compact
        pane = { "datasource" => uid, "queries" => [ { "refId" => "A", "datasource" => source }.merge(known.model.call(query)) ],
                 "range" => { "from" => from.to_s, "to" => to.to_s } }
        Telemetry::Link.new(provider: NAME, url: "#{address}/explore?#{{ schemaVersion: SCHEMA_VERSION, panes: { PANE => pane }.to_json }.to_query}")
      end

      private

      def type_of(uid)
        HealthProbes::Grafana::TYPES.flat_map { |type| HealthProbes::Grafana.datasources(@settings, type) }.find { |source| source["uid"] == uid }&.dig("type")
      end

      # Relative time is read against now, so the link shows what the call read rather than moving with the clock.
      def millis(value)
        relative = value.to_s.match(RELATIVE)
        time = if relative
          Time.current - (relative[:amount].to_i * UNITS.fetch(relative[:unit] || "s"))
        else
          Telemetry.parse_time(value)
        end
        (time.to_f * 1000).to_i if time
      end
    end
  end
end
