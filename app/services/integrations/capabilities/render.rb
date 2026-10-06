module Integrations
  module Capabilities
    # Render's own tools answer every capability as they are, by the resource's Render id. The change tools call the
    # restart, rollback and scale endpoints in Render's OpenAPI spec.
    module Render
      extend Adapter

      PACK = Packs::Render
      RUNNING = [ ResourceMap::KIND_SERVICE, ResourceMap::KIND_JOB, ResourceMap::KIND_DATABASE ].freeze
      DEPLOYED = [ ResourceMap::KIND_SERVICE, ResourceMap::KIND_JOB, ResourceMap::KIND_SITE ].freeze
      SUPPORTS = {
        LOGS => [ *RUNNING, ResourceMap::KIND_SITE ], METRICS => RUNNING, DEPLOYS => DEPLOYED,
        STATUS => [ *RUNNING, ResourceMap::KIND_SITE ], ROLLBACK => DEPLOYED,
        RESTART => [ ResourceMap::KIND_SERVICE, ResourceMap::KIND_DATABASE ], SCALE => [ ResourceMap::KIND_SERVICE ]
      }.freeze
      TOOLS = {
        LOGS => "search_logs", METRICS => "query_metrics", DEPLOYS => "list_deployments", STATUS => "describe_resource",
        ROLLBACK => "rollback_deploy", RESTART => "restart_service", SCALE => "scale_service"
      }.freeze
      WRAPPED = TOOLS.values.freeze
      STREAMS = { STREAM_APP => "app", "build" => "build", "requests" => "request" }.freeze
      METRIC_MAP = { "cpu" => "cpu", "memory" => "memory", "requests" => "requests", "http_4xx" => "http_4xx", "http_5xx" => "http_5xx",
                     "tcp_connections" => "active_connections", "latency_p95" => "latency_p95", "disk" => "disk" }.freeze

      def self.route(key, resource, given, tool: nil, settings: nil)
        id = resource.external_id
        case key
        when LOGS then Route.new(tool_name: TOOLS[LOGS], arguments: { "resource" => id, "type" => stream(given) }.compact.merge(logs(given)))
        when METRICS
          names = metric_names(given, METRIC_MAP, PACK::PROVIDER)
          Route.new(tool_name: TOOLS[METRICS], arguments: { "resource" => id, "metrics" => names.presence }.compact.merge(given.slice("minutes", "start", "end")))
        when DEPLOYS then Route.new(tool_name: TOOLS[DEPLOYS], arguments: { "resource" => id }.merge(given.slice("limit")))
        when STATUS then Route.new(tool_name: TOOLS[STATUS], arguments: { "resource" => id })
        when ROLLBACK then Route.new(tool_name: TOOLS[ROLLBACK], arguments: { "resource" => id, "deploy" => target(given) })
        when RESTART then Route.new(tool_name: TOOLS[RESTART], arguments: { "resource" => id })
        when SCALE then Route.new(tool_name: TOOLS[SCALE], arguments: { "resource" => id, "instances" => instances(given) })
        end
      end

      def self.stream(given)
        asked = given["stream"].presence
        return nil unless asked
        return STREAMS[asked] if STREAMS.key?(asked)

        raise Unroutable, "Render keeps app, build and request logs, so stream must be #{STREAMS.keys.join(', ')}."
      end

      # Render's log search takes text and a regular expression, and has no way to leave lines out.
      def self.logs(given)
        raise Unroutable, "Render's log search cannot leave lines out, so search by text or regex instead of exclude." if given["exclude"].present?

        given.slice("text", "regex", "limit", "minutes", "start", "end")
      end
      private_class_method :stream, :logs
    end
  end
end
