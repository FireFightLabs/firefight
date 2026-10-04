module Integrations
  module Capabilities
    # Railway's own tools answer every capability as they are, by the resource's Railway service id. The change tools
    # send the deploymentRestart, deploymentRollback and environmentPatchCommit mutations the Railway CLI uses.
    module Railway
      extend Adapter

      PACK = Packs::Railway
      RUNNING = [ ResourceMap::KIND_SERVICE, ResourceMap::KIND_DATABASE, ResourceMap::KIND_JOB ].freeze
      SUPPORTS = {
        LOGS => RUNNING, METRICS => RUNNING, DEPLOYS => RUNNING, STATUS => RUNNING, ROLLBACK => [ ResourceMap::KIND_SERVICE, ResourceMap::KIND_JOB ],
        RESTART => [ ResourceMap::KIND_SERVICE, ResourceMap::KIND_DATABASE ], SCALE => [ ResourceMap::KIND_SERVICE ]
      }.freeze
      TOOLS = {
        LOGS => "search_logs", METRICS => "query_metrics", DEPLOYS => "list_deployments", STATUS => "describe_resource",
        ROLLBACK => "rollback_deployment", RESTART => "restart_deployment", SCALE => "scale_service"
      }.freeze
      WRAPPED = TOOLS.values.freeze
      STREAMS = { STREAM_APP => PACK::APP, "build" => PACK::BUILD, "requests" => PACK::HTTP }.freeze
      METRIC_MAP = PACK::METRICS.index_with(&:itself).freeze

      def self.route(key, resource, given, tool: nil)
        id = resource.external_id
        case key
        when LOGS then Route.new(tool_name: TOOLS[LOGS], arguments: { "resource" => id, "type" => stream(given) }.compact.merge(logs(given)))
        when METRICS
          names = metric_names(given, METRIC_MAP, PACK::PROVIDER)
          Route.new(tool_name: TOOLS[METRICS], arguments: { "resource" => id, "metrics" => names.presence }.compact.merge(given.slice("minutes", "start", "end")))
        when DEPLOYS then Route.new(tool_name: TOOLS[DEPLOYS], arguments: { "resource" => id }.merge(given.slice("limit")))
        when STATUS then Route.new(tool_name: TOOLS[STATUS], arguments: { "resource" => id })
        when ROLLBACK then Route.new(tool_name: TOOLS[ROLLBACK], arguments: { "resource" => id, "deployment" => target(given) })
        when RESTART then Route.new(tool_name: TOOLS[RESTART], arguments: { "resource" => id })
        when SCALE then Route.new(tool_name: TOOLS[SCALE], arguments: { "resource" => id, "instances" => instances(given) })
        end
      end

      def self.stream(given)
        asked = given["stream"].presence
        return nil unless asked
        return STREAMS[asked] if STREAMS.key?(asked)

        raise Unroutable, "Railway keeps app, build and requests logs, so stream must be #{STREAMS.keys.join(', ')}."
      end

      # Railway's log filter matches text and leaves text out, and has no regular expressions.
      def self.logs(given)
        raise Unroutable, "Railway's log search has no regular expressions, so search by text, and leave lines out with exclude." if given["regex"].present?

        given.slice("text", "exclude", "limit", "minutes", "start", "end")
      end
      private_class_method :stream, :logs
    end
  end
end
