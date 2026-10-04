module Integrations
  module Capabilities
    # Fly.io's own tools answer every capability it has, by the app's name. A rollback updates each machine's image
    # through the Machines API, and a restart restarts each machine. Fly has no single call that sets how many machines
    # an app runs (fly scale count clones and destroys machines one by one, superfly/flyctl,
    # internal/command/scale/count_machines.go), so scale is not offered.
    module Fly
      extend Adapter

      PACK = Packs::Fly
      APP = [ ResourceMap::KIND_SERVICE ].freeze
      SUPPORTS = {
        LOGS => APP, METRICS => APP, DEPLOYS => APP, STATUS => [ *APP, ResourceMap::KIND_DATABASE ], ROLLBACK => APP, RESTART => APP
      }.freeze
      TOOLS = {
        LOGS => "search_logs", METRICS => "query_metrics", DEPLOYS => "list_deployments", STATUS => "describe_resource",
        ROLLBACK => "rollback_release", RESTART => "restart_app"
      }.freeze
      WRAPPED = TOOLS.values.freeze
      METRIC_MAP = PACK::METRICS.keys.index_with(&:itself).freeze
      PASSED = %w[text regex exclude limit minutes start end].freeze

      def self.route(key, resource, given, tool: nil)
        name = resource.external_id
        case key
        when LOGS
          if given["stream"].present? && given["stream"] != STREAM_APP
            raise Unroutable, "Fly.io keeps what an app prints, so stream must be #{STREAM_APP}."
          end

          Route.new(tool_name: TOOLS[LOGS], arguments: { "resource" => name }.merge(given.slice(*PASSED)))
        when METRICS
          names = metric_names(given, METRIC_MAP, PACK::PROVIDER)
          Route.new(tool_name: TOOLS[METRICS], arguments: { "resource" => name, "metrics" => names.presence }.compact.merge(given.slice("minutes", "start", "end")))
        when DEPLOYS then Route.new(tool_name: TOOLS[DEPLOYS], arguments: { "resource" => name }.merge(given.slice("limit")))
        when STATUS then Route.new(tool_name: TOOLS[STATUS], arguments: { "resource" => name })
        when ROLLBACK then Route.new(tool_name: TOOLS[ROLLBACK], arguments: { "resource" => name, "release" => target(given) })
        when RESTART then Route.new(tool_name: TOOLS[RESTART], arguments: { "resource" => name })
        end
      end
    end
  end
end
