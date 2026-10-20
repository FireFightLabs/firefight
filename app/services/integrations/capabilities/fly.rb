module Integrations
  module Capabilities
    # Fly.io's own tools answer every capability it has, by the app's name. A rollback updates each machine's image
    # through the Machines API, and a restart restarts each machine. Scale sets how many machines the app runs, adding
    # copies of its newest machine or destroying extras as fly scale count does, or, given a plan, the size its machines
    # run at as fly scale vm does (superfly/flyctl, internal/command/scale).
    module Fly
      extend Adapter

      PACK = Packs::Fly
      APP = [ ResourceMap::KIND_SERVICE ].freeze
      SUPPORTS = {
        LOGS => APP, METRICS => APP, DEPLOYS => APP, HISTORY => APP, STATUS => [ *APP, ResourceMap::KIND_DATABASE ], ROLLBACK => APP, RESTART => APP,
        SCALE => APP
      }.freeze
      TOOLS = {
        LOGS => "search_logs", METRICS => "query_metrics", DEPLOYS => "list_deployments", STATUS => "describe_resource",
        HISTORY => "deploy_history", ROLLBACK => "rollback_release", RESTART => "restart_app", SCALE => %w[scale_app resize_app]
      }.freeze
      # scale_app takes a process group and resize_app memory, which the capability cannot name, so both stay offered.
      WRAPPED = (TOOLS.values.flatten - TOOLS[SCALE]).freeze
      METRIC_MAP = PACK::METRICS.keys.index_with(&:itself).freeze
      PASSED = %w[text regex exclude limit minutes start end].freeze

      def self.takes_plan? = true

      def self.route(key, resource, given, tool: nil, settings: nil)
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
        when HISTORY then Route.new(tool_name: TOOLS[HISTORY], arguments: { "resource" => name }.merge(given.slice("name", "run", "limit").compact_blank))
        when ROLLBACK then Route.new(tool_name: TOOLS[ROLLBACK], arguments: { "resource" => name, "release" => target(given) })
        when RESTART then Route.new(tool_name: TOOLS[RESTART], arguments: { "resource" => name })
        when SCALE then scale(name, given)
        end
      end

      # A plan is one of the sizes fly scale vm takes and resizes every machine. A count and a size are two changes, so
      # they are asked one at a time.
      def self.scale(name, given)
        count, resize = tools_for(SCALE)
        plan = given[PLAN_ARG].to_s.strip
        return Route.new(tool_name: count, arguments: { "resource" => name, "instances" => instances(given) }) if plan.empty?
        raise Unroutable, "Change how many machines run and their size one at a time." if given["instances"].present?
        raise Unroutable, "Fly.io sizes are #{PACK::SIZES.keys.join(', ')}." unless PACK::SIZES.key?(plan)

        Route.new(tool_name: resize, arguments: { "resource" => name, "size" => plan })
      end
      private_class_method :scale
    end
  end
end
