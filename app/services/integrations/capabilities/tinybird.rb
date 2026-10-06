module Integrations
  module Capabilities
    # Tinybird answers through its pack's own tools, one connection per workspace. The workspace and its data sources are
    # databases on the map and its API endpoints functions, told apart by the type the map keeps in their details. Logs
    # are an endpoint's requests or a data source's operations, errors what failed, metrics an endpoint's requests over
    # time, and deploys the workspace's deployment jobs, all from Tinybird's service data sources. Tinybird documents no
    # rollback, restart or scale, and keeps no metrics for a data source, so those are not offered.
    module Tinybird
      extend Adapter

      PACK = Packs::Tinybird
      DATABASE = ResourceMap::KIND_DATABASE
      FUNCTION = ResourceMap::KIND_FUNCTION
      REQUESTS = "requests".freeze
      REQUEST_LOG = "endpoint_requests".freeze
      OPERATION_LOG = "datasource_operations".freeze
      METRICS_TOOL = "endpoint_metrics".freeze
      JOBS = "jobs".freeze
      SUPPORTS = {
        LOGS => [ DATABASE, FUNCTION ], METRICS => [ DATABASE, FUNCTION ], DEPLOYS => [ DATABASE, FUNCTION ],
        STATUS => [ DATABASE, FUNCTION ], ERRORS => [ DATABASE, FUNCTION ]
      }.freeze
      TOOLS = {
        LOGS => [ REQUEST_LOG, OPERATION_LOG ], METRICS => METRICS_TOOL, DEPLOYS => JOBS, STATUS => "describe_resource", ERRORS => "list_errors"
      }.freeze
      # The status and errors tools answer one to one. The logs, metrics and jobs tools also read what no capability asks,
      # such as one endpoint's latency or a copy job, so they stay offered.
      WRAPPED = [ TOOLS[STATUS], TOOLS[ERRORS] ].freeze
      # The capability's metric names, which the pack's tool takes as they are.
      METRIC_NAMES_READ = %w[requests errors http_4xx http_5xx cpu_time latency_p95].to_h { |name| [ name, name ] }.freeze
      RANGE_ARGS = %w[minutes start end].freeze
      LOG_ARGS = [ "text", "regex", "exclude", "limit", *RANGE_ARGS ].freeze

      # A resource's id, or nothing for the workspace, which every tool reads when it names no data source or endpoint.
      def self.named(resource) = workspace?(resource) ? {} : { "name" => resource.external_id }

      def self.workspace?(resource) = resource.details.to_h["type"] == PACK::TYPE_WORKSPACE

      def self.datasource?(resource) = resource.kind == DATABASE && !workspace?(resource)

      def self.route(key, resource, given, tool: nil, settings: nil)
        case key
        when LOGS then logs(resource, given)
        when METRICS
          raise Unroutable, "Tinybird keeps request metrics for API endpoints and the workspace, not for a data source. Ask for its logs instead." if datasource?(resource)

          names = metric_names(given, METRIC_NAMES_READ, PACK::PROVIDER)
          endpoint = workspace?(resource) ? {} : { "endpoint" => resource.external_id }
          Route.new(tool_name: METRICS_TOOL, arguments: endpoint.merge("metrics" => names.presence).compact.merge(given.slice(*RANGE_ARGS)))
        when DEPLOYS then Route.new(tool_name: JOBS, arguments: { "job_type" => PACK::Queries::JOB_DEPLOYMENT }.merge(given.slice("limit")))
        when STATUS then Route.new(tool_name: TOOLS[STATUS], arguments: named(resource))
        when ERRORS then Route.new(tool_name: TOOLS[ERRORS], arguments: named(resource).merge(given.slice("text", "limit", *RANGE_ARGS)))
        end
      end

      # Stream requests reads the requests an endpoint or the workspace answered, and stream app, the default, what a
      # data source's operations did, or an endpoint's requests, which are all it has.
      def self.logs(resource, given)
        stream = given["stream"].presence
        unless [ nil, STREAM_APP, REQUESTS ].include?(stream)
          raise Unroutable, "Tinybird keeps the requests endpoints answered (stream requests) and what data source operations did (stream app), nothing else."
        end

        passed = given.slice(*LOG_ARGS)
        if resource.kind == FUNCTION || (workspace?(resource) && stream == REQUESTS)
          endpoint = workspace?(resource) ? {} : { "endpoint" => resource.external_id }
          return Route.new(tool_name: REQUEST_LOG, arguments: endpoint.merge(passed))
        end
        raise Unroutable, "A Tinybird data source answers no requests. Its operations are stream app, and the endpoints that read it have the requests." if stream == REQUESTS

        datasource = workspace?(resource) ? {} : { "datasource" => resource.external_id }
        Route.new(tool_name: OPERATION_LOG, arguments: datasource.merge(passed))
      end

      # Deployments belong to the whole workspace, so the details say so.
      def self.phrase(key) = key == DEPLOYS ? "see the workspace's deployments" : super

      private_class_method :named, :workspace?, :datasource?, :logs
    end
  end
end
