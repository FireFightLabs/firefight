module Integrations
  module Capabilities
    # Azure's pack answers every capability with a tool of its own, by the resource's Resource Manager id. Its metrics
    # already take the names every capability uses, so only the ones Azure Monitor keeps for each kind of resource are
    # passed on. A rollback swaps an App Service slot or moves a Container App's traffic, whichever the resource is. Run
    # history is an App Service or Function app's deployments, which keep when each started and ended. A Container App
    # revision keeps only when it was made, so it has none.
    module Azure
      extend Adapter

      SERVICE = ResourceMap::KIND_SERVICE
      DATABASE = ResourceMap::KIND_DATABASE
      SUPPORTS = {
        LOGS => [ SERVICE, DATABASE ], METRICS => [ SERVICE, DATABASE ], DEPLOYS => [ SERVICE ], HISTORY => [ SERVICE ], STATUS => [ SERVICE, DATABASE ],
        ROLLBACK => [ SERVICE ], RESTART => [ SERVICE, DATABASE ], SCALE => [ SERVICE ]
      }.freeze
      TOOLS = {
        LOGS => "search_logs", METRICS => "query_metrics", DEPLOYS => "list_deployments", HISTORY => "list_deployments", STATUS => "describe_resource",
        ROLLBACK => "rollback_app", RESTART => "restart_resource", SCALE => "scale_app"
      }.freeze
      # Every tool, the changes too, is answered one to one, so Halon is offered the capability and never the tool as well.
      WRAPPED = TOOLS.values.uniq.freeze
      PASSED = %w[text regex exclude stream limit minutes start end].freeze

      # A restart reaches only some kinds, so the details say which.
      def self.phrase(key) = key == RESTART ? "restart an app or a PostgreSQL server" : super

      def self.route(key, resource, given, tool: nil, settings: nil)
        id = resource.external_id
        case key
        when LOGS then Route.new(tool_name: TOOLS[LOGS], arguments: { "resource" => id }.merge(given.slice(*PASSED)))
        when METRICS
          names = metric_names(given, Packs::Azure::Metrics.names(resource.details.to_h[Packs::Azure::TYPE]), Packs::Azure::PROVIDER)
          Route.new(tool_name: TOOLS[METRICS], arguments: { "resource" => id, "metrics" => names.presence }.compact.merge(given.slice("minutes", "start", "end")))
        when DEPLOYS then Route.new(tool_name: TOOLS[DEPLOYS], arguments: { "resource" => id }.merge(given.slice("limit")))
        when STATUS then Route.new(tool_name: TOOLS[STATUS], arguments: { "resource" => id })
        when HISTORY then history(resource, given)
        when ROLLBACK then Route.new(tool_name: TOOLS[ROLLBACK], arguments: { "resource" => id, "to" => target(given) })
        when RESTART then Route.new(tool_name: TOOLS[RESTART], arguments: { "resource" => id })
        when SCALE then Route.new(tool_name: TOOLS[SCALE], arguments: { "resource" => id, "instances" => instances(given) })
        end
      end

      def self.history(resource, given)
        if resource.details.to_h[Packs::Azure::TYPE] == Packs::Azure::TYPE_CONTAINER
          raise Unroutable, "Azure keeps when each revision of #{resource.name} was made, not when it finished rolling out, so it has no run " \
                            "history to time. Ask for its deploys instead."
        end

        Route.new(tool_name: TOOLS[HISTORY], arguments: { "resource" => resource.external_id, "limit" => Answers.limit(given, History::LIMIT) },
                  present: RunHistory.presenter(resource.name, given))
      end
      private_class_method :history
    end
  end
end
