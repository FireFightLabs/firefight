module Integrations
  module Capabilities
    # Azure's pack answers every capability with a tool of its own, by the resource's Resource Manager id. Its metrics
    # already take the names every capability uses, so only the ones Azure Monitor keeps for each kind of resource are
    # passed on. A rollback swaps an App Service slot or moves a Container App's traffic, whichever the resource is.
    module Azure
      extend Adapter

      SERVICE = ResourceMap::KIND_SERVICE
      DATABASE = ResourceMap::KIND_DATABASE
      SUPPORTS = {
        LOGS => [ SERVICE, DATABASE ], METRICS => [ SERVICE, DATABASE ], DEPLOYS => [ SERVICE ], STATUS => [ SERVICE, DATABASE ],
        ROLLBACK => [ SERVICE ], RESTART => [ SERVICE, DATABASE ], SCALE => [ SERVICE ]
      }.freeze
      TOOLS = {
        LOGS => "search_logs", METRICS => "query_metrics", DEPLOYS => "list_deployments", STATUS => "describe_resource",
        ROLLBACK => "rollback_app", RESTART => "restart_resource", SCALE => "scale_app"
      }.freeze
      CHANGES = [ ROLLBACK, RESTART, SCALE ].freeze
      WRAPPED = TOOLS.except(*CHANGES).values.freeze
      PASSED = %w[text regex exclude stream limit minutes start end].freeze

      def self.route(key, resource, given, tool: nil, settings: nil)
        id = resource.external_id
        case key
        when LOGS then Route.new(tool_name: TOOLS[LOGS], arguments: { "resource" => id }.merge(given.slice(*PASSED)))
        when METRICS
          names = metric_names(given, Packs::Azure::Metrics.names(resource.details.to_h[Packs::Azure::TYPE]), Packs::Azure::PROVIDER)
          Route.new(tool_name: TOOLS[METRICS], arguments: { "resource" => id, "metrics" => names.presence }.compact.merge(given.slice("minutes", "start", "end")))
        when DEPLOYS then Route.new(tool_name: TOOLS[DEPLOYS], arguments: { "resource" => id }.merge(given.slice("limit")))
        when STATUS then Route.new(tool_name: TOOLS[STATUS], arguments: { "resource" => id })
        when ROLLBACK then Route.new(tool_name: TOOLS[ROLLBACK], arguments: { "resource" => id, "to" => target(given) })
        when RESTART then Route.new(tool_name: TOOLS[RESTART], arguments: { "resource" => id })
        when SCALE then Route.new(tool_name: TOOLS[SCALE], arguments: { "resource" => id, "instances" => instances(given) })
        end
      end
    end
  end
end
