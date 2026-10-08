module Integrations
  module Capabilities
    # Northflank's own tools answer most capabilities as they are, by the resource's Northflank id. A rollback, restart or
    # scale goes through api_request with the paths its fixes skill gives.
    module Northflank
      extend Adapter

      RUNNING = [ ResourceMap::KIND_SERVICE, ResourceMap::KIND_DATABASE ].freeze
      SUPPORTS = {
        LOGS => [ *RUNNING, ResourceMap::KIND_BUILD_SERVICE ], METRICS => RUNNING, DEPLOYS => [ ResourceMap::KIND_SERVICE ],
        STATUS => RUNNING, HISTORY => [ ResourceMap::KIND_SERVICE, ResourceMap::KIND_BUILD_SERVICE ], ROLLBACK => [ ResourceMap::KIND_SERVICE ], RESTART => [ ResourceMap::KIND_SERVICE ],
        SCALE => [ ResourceMap::KIND_SERVICE ]
      }.freeze
      API = "api_request".freeze
      TOOLS = {
        LOGS => "search_logs", METRICS => "query_metrics", DEPLOYS => "list_deployments", STATUS => "describe_resource",
        HISTORY => "build_history", ROLLBACK => API, RESTART => API, SCALE => API
      }.freeze
      WRAPPED = TOOLS.values.uniq.excluding(API).freeze
      STREAMS = { "app" => "runtime", "build" => "build", "requests" => "ingress", "internal" => "mesh", "cdn" => "cdn", "backup" => "backup", "restore" => "restore" }.freeze
      METRIC_MAP = {
        "cpu" => "cpu", "memory" => "memory", "requests" => "requests", "http_4xx" => "http4xxResponses",
        "http_5xx" => "http5xxResponses", "network_in" => "networkIngress", "network_out" => "networkEgress",
        "tcp_connections" => "tcpConnectionsOpen", "disk" => "diskUsage", "bandwidth" => "bandwidth"
      }.freeze
      PASSED = %w[text regex exclude limit minutes start end].freeze

      def self.route(key, resource, given, tool: nil, settings: nil)
        id = resource.external_id
        case key
        when LOGS
          # A build service only builds, so its logs are its builds' unless the request says otherwise.
          stream = given["stream"].presence || ("build" if resource.kind == ResourceMap::KIND_BUILD_SERVICE)
          Route.new(tool_name: TOOLS[LOGS], arguments: { "resource" => id, "type" => STREAMS[stream.to_s] }.compact.merge(given.slice(*PASSED)))
        when METRICS
          names = metric_names(given, METRIC_MAP, "Northflank")
          Route.new(tool_name: TOOLS[METRICS], arguments: { "resource" => id, "metrics" => names.presence }.compact.merge(given.slice("minutes", "start", "end")))
        when DEPLOYS then Route.new(tool_name: TOOLS[DEPLOYS], arguments: { "resource" => id }.merge(given.slice("limit")))
        when STATUS then Route.new(tool_name: TOOLS[STATUS], arguments: { "resource" => id })
        # A service that runs another's builds has none of its own, so its history is the builds of the one that builds it.
        when HISTORY then Route.new(tool_name: TOOLS[HISTORY], arguments: { "resource" => builder_of(resource) }.merge(given.slice("name", "limit")))
        when ROLLBACK then change("services/#{id}/deployment", { "internal" => { "id" => builder_of(resource), "buildId" => target(given) } })
        when RESTART then change("services/#{id}/restart")
        when SCALE then change("services/#{id}/scale", { "instances" => instances(given) })
        end
      end

      def self.change(path, body = nil) = Route.new(tool_name: API, arguments: { "method" => "POST", "path" => path, "body" => body }.compact)

      # The service whose builds a rollback deploys: the build service it runs builds of, or itself when it builds its own.
      def self.builder_of(resource)
        built = ResourceMap::Link.facts.where(from_resource: resource, relation: ResourceMap::RELATION_RUNS_BUILDS_OF, origin: ResourceMap::ORIGIN_DECLARED)
                                 .joins(:to_resource).merge(ResourceMap::Resource.present).order(:created_at).first&.to_resource
        built&.external_id || resource.external_id
      end
      private_class_method :change, :builder_of
    end
  end
end
