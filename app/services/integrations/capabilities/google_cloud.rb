module Integrations
  module Capabilities
    # Google Cloud's pack answers every capability with a tool of its own, by the resource's id on the map. Its metrics
    # already take the names every capability uses, so only the ones Google keeps for each kind of resource are passed
    # on (Packs::GoogleCloud::Metrics). Revisions, errors, a rollback and scaling are Cloud Run's, and a restart is
    # Cloud SQL's or a Compute Engine instance's, since Cloud Run has none.
    module GoogleCloud
      extend Adapter

      SERVICE = ResourceMap::KIND_SERVICE
      DATABASE = ResourceMap::KIND_DATABASE
      MACHINE = ResourceMap::KIND_VIRTUAL_MACHINE
      CLUSTER = ResourceMap::KIND_CLUSTER
      SUPPORTS = {
        LOGS => [ SERVICE, DATABASE, MACHINE, CLUSTER ], METRICS => [ SERVICE, DATABASE, MACHINE ], DEPLOYS => [ SERVICE ],
        STATUS => [ SERVICE, DATABASE, MACHINE, CLUSTER ], ERRORS => [ SERVICE ], ROLLBACK => [ SERVICE ],
        RESTART => [ DATABASE, MACHINE ], SCALE => [ SERVICE ]
      }.freeze
      TOOLS = {
        LOGS => "search_logs", METRICS => "query_metrics", DEPLOYS => "list_revisions", STATUS => "describe_resource",
        ERRORS => "error_groups", ROLLBACK => "rollback_service", RESTART => "restart_resource", SCALE => "scale_service"
      }.freeze
      CHANGES = [ ROLLBACK, RESTART, SCALE ].freeze
      WRAPPED = TOOLS.except(*CHANGES).values.freeze
      PASSED = %w[text regex exclude stream limit minutes start end].freeze

      def self.route(key, resource, given, tool: nil, settings: nil)
        id = resource.external_id
        case key
        when LOGS then Route.new(tool_name: TOOLS[LOGS], arguments: { "resource" => id }.merge(given.slice(*PASSED)))
        when METRICS
          names = metric_names(given, Packs::GoogleCloud::Metrics.names(resource.kind), Packs::GoogleCloud::PROVIDER)
          Route.new(tool_name: TOOLS[METRICS], arguments: { "resource" => id, "metrics" => names.presence }.compact.merge(given.slice("minutes", "start", "end")))
        when DEPLOYS then Route.new(tool_name: TOOLS[DEPLOYS], arguments: { "resource" => id }.merge(given.slice("limit")))
        when STATUS then Route.new(tool_name: TOOLS[STATUS], arguments: { "resource" => id })
        when ERRORS then Route.new(tool_name: TOOLS[ERRORS], arguments: { "resource" => id }.merge(given.slice("text", "limit", "minutes", "start", "end")))
        when ROLLBACK then Route.new(tool_name: TOOLS[ROLLBACK], arguments: { "resource" => id, "revision" => target(given) })
        when RESTART then Route.new(tool_name: TOOLS[RESTART], arguments: { "resource" => id })
        when SCALE then Route.new(tool_name: TOOLS[SCALE], arguments: { "resource" => id, "min_instances" => instances(given) })
        end
      end
    end
  end
end
