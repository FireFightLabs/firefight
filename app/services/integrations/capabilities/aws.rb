module Integrations
  module Capabilities
    # AWS's own tools answer each capability as they are, by the resource's ARN, which the map keeps as its id. A
    # rollback, restart or scale runs the pack's tool for that change, so each is its own action to grant and approve.
    # The capability metric names map onto the CloudWatch metrics AWS documents as the same reading for each kind:
    # CPUUtilization and MemoryUtilization for an ECS service, Invocations (each run of the function, its requests) and
    # Errors for a Lambda function, CPUUtilization, NetworkIn and NetworkOut for an EC2 instance, and CPUUtilization and
    # DatabaseConnections (its client network connections) for an RDS database.
    module Aws
      extend Adapter

      PACK = Packs::Aws
      SUPPORTS = {
        LOGS => [ PACK::SERVICE, PACK::FUNCTION, PACK::DATABASE ],
        METRICS => [ PACK::SERVICE, PACK::FUNCTION, PACK::INSTANCE, PACK::DATABASE ],
        DEPLOYS => [ PACK::SERVICE, PACK::FUNCTION ],
        STATUS => [ PACK::SERVICE, PACK::FUNCTION, PACK::INSTANCE, PACK::DATABASE ],
        ROLLBACK => [ PACK::SERVICE, PACK::FUNCTION ],
        RESTART => [ PACK::SERVICE ],
        SCALE => [ PACK::SERVICE ]
      }.freeze
      TOOLS = {
        LOGS => "search_logs", METRICS => "cloudwatch_metrics", DEPLOYS => "list_deployments", STATUS => "describe_resource",
        ROLLBACK => "rollback_deployment", RESTART => "restart_service", SCALE => "scale_service"
      }.freeze
      # Each tool answers one capability for one resource, so an agent holding the capability is not offered it as well.
      # cloudwatch_metrics reads every metric AWS documents for each kind, beyond the ones a capability names, so it stays
      # offered as it is.
      WRAPPED = TOOLS.values.excluding(TOOLS[METRICS]).freeze
      METRIC_MAP = {
        PACK::SERVICE => { "cpu" => "CPUUtilization", "memory" => "MemoryUtilization" },
        PACK::FUNCTION => { "requests" => "Invocations", "errors" => "Errors" },
        PACK::INSTANCE => { "cpu" => "CPUUtilization", "network_in" => "NetworkIn", "network_out" => "NetworkOut" },
        PACK::DATABASE => { "cpu" => "CPUUtilization", "tcp_connections" => "DatabaseConnections" }
      }.freeze
      PASSED = %w[text regex exclude limit minutes start end].freeze
      RANGE = %w[minutes start end].freeze

      def self.route(key, resource, given, tool: nil, settings: nil)
        arn = resource.external_id
        case key
        when LOGS
          unless given["stream"].in?([ nil, "", STREAM_APP ])
            raise Unroutable, "AWS keeps what #{resource.name} prints in CloudWatch Logs, so stream must be #{STREAM_APP}."
          end

          Route.new(tool_name: TOOLS[LOGS], arguments: { "resource" => arn }.merge(given.slice(*PASSED)))
        when METRICS
          names = metric_names(given, METRIC_MAP.fetch(resource.kind), PACK::PROVIDER)
          Route.new(tool_name: TOOLS[METRICS], arguments: { "resource" => arn, "metrics" => names.presence }.compact.merge(given.slice(*RANGE)))
        when DEPLOYS then Route.new(tool_name: TOOLS[DEPLOYS], arguments: { "resource" => arn }.merge(given.slice("limit")))
        when STATUS then Route.new(tool_name: TOOLS[STATUS], arguments: { "resource" => arn })
        when ROLLBACK then Route.new(tool_name: TOOLS[ROLLBACK], arguments: { "resource" => arn, "to" => target(given) })
        when RESTART then Route.new(tool_name: TOOLS[RESTART], arguments: { "resource" => arn })
        when SCALE then Route.new(tool_name: TOOLS[SCALE], arguments: { "resource" => arn, "desired_count" => instances(given) })
        end
      end
    end
  end
end
