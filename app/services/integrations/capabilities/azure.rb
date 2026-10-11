module Integrations
  module Capabilities
    # Azure's pack answers every capability with a tool of its own, by the resource's Resource Manager id. Its metrics
    # already take the names every capability uses, so only the ones Azure Monitor keeps for each kind of resource are
    # passed on. A rollback swaps an App Service slot or moves a Container App's traffic, whichever the resource is. Run
    # history is an App Service or Function app's deployments, which keep when each started and ended, one read by its id
    # with the steps its log records. Their build stream is a deployment's log. A Container App revision keeps only when
    # it was made, so it has none.
    module Azure
      extend Adapter

      SERVICE = ResourceMap::KIND_SERVICE
      DATABASE = ResourceMap::KIND_DATABASE
      SUPPORTS = {
        LOGS => [ SERVICE, DATABASE ], METRICS => [ SERVICE, DATABASE ], DEPLOYS => [ SERVICE ], HISTORY => [ SERVICE ], STATUS => [ SERVICE, DATABASE ],
        ROLLBACK => [ SERVICE ], RESTART => [ SERVICE, DATABASE ], SCALE => [ SERVICE ]
      }.freeze
      DEPLOYMENT_LOG = "deployment_log".freeze
      TOOLS = {
        LOGS => [ "search_logs", DEPLOYMENT_LOG ], METRICS => "query_metrics", DEPLOYS => "list_deployments", HISTORY => "list_deployments",
        STATUS => "describe_resource", ROLLBACK => "rollback_app", RESTART => "restart_resource", SCALE => "scale_app"
      }.freeze
      # Every tool, the changes too, is answered one to one, so Halon is offered the capability and never the tool as well.
      WRAPPED = TOOLS.values.flatten.uniq.freeze
      PASSED = %w[text regex exclude stream limit minutes start end].freeze
      SITES = [ Packs::Azure::TYPE_WEB, Packs::Azure::TYPE_FUNCTION ].freeze

      # A restart reaches only some kinds, so the details say which.
      def self.phrase(key) = key == RESTART ? "restart an app or a PostgreSQL server" : super

      def self.route(key, resource, given, tool: nil, settings: nil)
        id = resource.external_id
        case key
        when LOGS then logs(resource, given)
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

      # An app's build logs are its deployments' logs, the one named or the newest.
      def self.logs(resource, given)
        return Route.new(tool_name: TOOLS[LOGS].first, arguments: { "resource" => resource.external_id }.merge(given.slice(*PASSED))) unless given["stream"] == STREAM_BUILD
        unless SITES.include?(resource.details.to_h[Packs::Azure::TYPE])
          raise Unroutable, "Azure keeps build logs for an App Service or Function app's deployments, and #{resource.name} is not one. Ask for its app logs instead."
        end

        Route.new(tool_name: DEPLOYMENT_LOG, arguments: { "resource" => resource.external_id, "deployment" => given["deployment"].presence }.compact)
      end

      def self.history(resource, given)
        if resource.details.to_h[Packs::Azure::TYPE] == Packs::Azure::TYPE_CONTAINER
          raise Unroutable, "Azure keeps when each revision of #{resource.name} was made, not when it finished rolling out, so it has no run " \
                            "history to time. Ask for its deploys instead."
        end

        arguments = { "resource" => resource.external_id, "deployment" => given["run"].to_s.strip.presence, "limit" => Answers.limit(given, History::LIMIT) }
        Route.new(tool_name: TOOLS[HISTORY], arguments: arguments.compact, present: RunHistory.presenter(resource.name, given))
      end
      private_class_method :logs, :history
    end
  end
end
