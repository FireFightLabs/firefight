module Integrations
  module Capabilities
    # AWS's own tools answer each capability as they are, by the resource's ARN, which the map keeps as its id. A
    # rollback, restart or scale runs the pack's tool for that change, so each is its own action to grant and approve.
    # The capability metric names map onto the CloudWatch metrics AWS documents as the same reading for each kind:
    # CPUUtilization and MemoryUtilization for an ECS service, Invocations (each run of the function, its requests),
    # Errors, Duration and Throttles for a Lambda function, CPUUtilization, NetworkIn and NetworkOut for an EC2 instance,
    # and CPUUtilization, DatabaseConnections (its client network connections), FreeableMemory and FreeStorageSpace for an
    # RDS database. RDS reports the memory and storage left rather than used, and its charts say so. Run history is an
    # ECS service's deployments, which keep when each started and finished, and a CodeBuild project's builds. One run
    # asked by its id is read with its rollout and rollback, or its phases. A Lambda version keeps only when it was made.
    # A CodeBuild project's logs are its builds' logs, read as the build stream, of the build asked for or the newest.
    module Aws
      extend Adapter

      PACK = Packs::Aws
      SUPPORTS = {
        LOGS => [ PACK::SERVICE, PACK::FUNCTION, PACK::DATABASE, PACK::PROJECT ],
        METRICS => [ PACK::SERVICE, PACK::FUNCTION, PACK::INSTANCE, PACK::DATABASE ],
        DEPLOYS => [ PACK::SERVICE, PACK::FUNCTION ],
        HISTORY => [ PACK::SERVICE, PACK::PROJECT ],
        STATUS => [ PACK::SERVICE, PACK::FUNCTION, PACK::INSTANCE, PACK::DATABASE, PACK::PROJECT ],
        ROLLBACK => [ PACK::SERVICE, PACK::FUNCTION ],
        RESTART => [ PACK::SERVICE ],
        SCALE => [ PACK::SERVICE ]
      }.freeze
      SEARCH_LOGS = "search_logs".freeze
      BUILD_LOG = "build_log".freeze
      DEPLOYMENTS = "list_deployments".freeze
      BUILDS = "list_builds".freeze
      TOOLS = {
        LOGS => [ SEARCH_LOGS, BUILD_LOG ], METRICS => "cloudwatch_metrics", DEPLOYS => DEPLOYMENTS, HISTORY => [ DEPLOYMENTS, BUILDS ],
        STATUS => "describe_resource", ROLLBACK => "rollback_deployment", RESTART => "restart_service", SCALE => "scale_service"
      }.freeze
      # Each tool answers one capability for one resource, so an agent holding the capability is not offered it as well.
      # cloudwatch_metrics reads every metric AWS documents for each kind, beyond the ones a capability names, and
      # build_log reads any build of a project by its id, so both stay offered as they are.
      WRAPPED = TOOLS.values.flatten.uniq.excluding(TOOLS[METRICS], BUILD_LOG).freeze
      METRIC_MAP = {
        PACK::SERVICE => { "cpu" => "CPUUtilization", "memory" => "MemoryUtilization" },
        PACK::FUNCTION => { "requests" => "Invocations", "invocations" => "Invocations", "errors" => "Errors", "duration" => "Duration",
                            "throttles" => "Throttles" },
        PACK::INSTANCE => { "cpu" => "CPUUtilization", "network_in" => "NetworkIn", "network_out" => "NetworkOut" },
        PACK::DATABASE => { "cpu" => "CPUUtilization", "tcp_connections" => "DatabaseConnections", "memory" => "FreeableMemory",
                            "disk" => "FreeStorageSpace" }
      }.freeze
      PASSED = %w[text regex exclude limit minutes start end].freeze
      BUILD_PASSED = %w[text regex exclude limit].freeze
      RANGE = %w[minutes start end].freeze

      def self.route(key, resource, given, tool: nil, settings: nil)
        arn = resource.external_id
        case key
        when LOGS then logs(resource, given)
        when METRICS
          names = metric_names(given, METRIC_MAP.fetch(resource.kind), PACK::PROVIDER)
          Route.new(tool_name: TOOLS[METRICS], arguments: { "resource" => arn, "metrics" => names.presence }.compact.merge(given.slice(*RANGE)))
        when DEPLOYS then Route.new(tool_name: TOOLS[DEPLOYS], arguments: { "resource" => arn }.merge(given.slice("limit")))
        when STATUS then Route.new(tool_name: TOOLS[STATUS], arguments: { "resource" => arn })
        when HISTORY
          arguments = { "resource" => arn, "run" => given["run"].to_s.strip.presence, "limit" => Answers.limit(given, History::LIMIT) }.compact
          Route.new(tool_name: resource.kind == PACK::PROJECT ? BUILDS : DEPLOYMENTS, arguments: arguments, present: RunHistory.presenter(resource.name, given))
        when ROLLBACK then Route.new(tool_name: TOOLS[ROLLBACK], arguments: { "resource" => arn, "to" => target(given) })
        when RESTART then Route.new(tool_name: TOOLS[RESTART], arguments: { "resource" => arn })
        when SCALE then Route.new(tool_name: TOOLS[SCALE], arguments: { "resource" => arn, "desired_count" => instances(given) })
        end
      end

      def self.logs(resource, given)
        stream = given["stream"].presence
        if resource.kind == PACK::PROJECT
          unless stream.in?([ nil, STREAM_BUILD ])
            raise Unroutable, "AWS keeps the build logs of #{resource.name}, a CodeBuild project, so stream must be #{STREAM_BUILD}."
          end

          arguments = { "resource" => resource.external_id, "build" => given["deployment"].to_s.strip.presence }.compact
          return Route.new(tool_name: BUILD_LOG, arguments: arguments.merge(given.slice(*BUILD_PASSED)))
        end
        raise Unroutable, "AWS keeps what #{resource.name} prints in CloudWatch Logs, so stream must be #{STREAM_APP}." unless stream.in?([ nil, STREAM_APP ])

        Route.new(tool_name: SEARCH_LOGS, arguments: { "resource" => resource.external_id }.merge(given.slice(*PASSED)))
      end
      private_class_method :logs
    end
  end
end
