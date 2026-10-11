module Integrations
  module Capabilities
    # AWS's own tools answer each capability as they are, by the resource's ARN, which the map keeps as its id. A
    # rollback, restart or scale runs the pack's tool for that change, so each is its own action to grant and approve.
    # The capability metric names map onto the CloudWatch metrics AWS documents as the same reading for each kind:
    # CPUUtilization and MemoryUtilization for an ECS service, Invocations (each run of the function, its requests),
    # Errors, Duration and Throttles for a Lambda function, CPUUtilization, NetworkIn and NetworkOut for an EC2 instance,
    # and CPUUtilization, DatabaseConnections (its client network connections), FreeableMemory and FreeStorageSpace for an
    # RDS database. RDS reports the memory and storage left rather than used, and its charts say so. Run history is an
    # ECS service's deployments, which keep when each started and finished, a CodeBuild project's builds, a CodePipeline
    # pipeline's executions, a CodeDeploy deployment group's deployments, a CloudFormation stack's operations, an App
    # Runner service's operations and an Elastic Beanstalk environment's deploys. One run asked by its id is read with
    # its steps. A Lambda version keeps only when it was made. A CodeBuild project's logs are its builds' logs, read as
    # the build stream, of the build asked for or the newest.
    #
    # An App Runner service and an Elastic Beanstalk environment are services on the map beside ECS's, told apart by their
    # ARN. They answer status, deploys and run history, and a request Firefight cannot make of them is refused in words.
    # A rollback of something releasing stops or undoes the release going now: an ECS deployment by its id, a stage of
    # a pipeline back to an earlier execution, a CodeDeploy deployment rolled back, a stack update cancelled.
    module Aws
      extend Adapter

      PACK = Packs::Aws
      RELEASES = PACK::Releases
      PLATFORMS = PACK::AppPlatforms
      SUPPORTS = {
        LOGS => [ PACK::SERVICE, PACK::FUNCTION, PACK::DATABASE, PACK::PROJECT ],
        METRICS => [ PACK::SERVICE, PACK::FUNCTION, PACK::INSTANCE, PACK::DATABASE ],
        DEPLOYS => [ PACK::SERVICE, PACK::FUNCTION ],
        HISTORY => [ PACK::SERVICE, PACK::PROJECT, RELEASES::PIPELINE, RELEASES::DEPLOYMENT_GROUP, RELEASES::STACK ],
        STATUS => [ PACK::SERVICE, PACK::FUNCTION, PACK::INSTANCE, PACK::DATABASE, PACK::PROJECT ],
        ROLLBACK => [ PACK::SERVICE, PACK::FUNCTION, RELEASES::PIPELINE, RELEASES::DEPLOYMENT_GROUP, RELEASES::STACK ],
        RESTART => [ PACK::SERVICE ],
        SCALE => [ PACK::SERVICE ]
      }.freeze
      SEARCH_LOGS = "search_logs".freeze
      BUILD_LOG = "build_log".freeze
      DEPLOYMENTS = "list_deployments".freeze
      BUILDS = "list_builds".freeze
      HISTORIES = {
        RELEASES::PIPELINE => RELEASES::PIPELINE_EXECUTIONS, RELEASES::DEPLOYMENT_GROUP => RELEASES::CODEDEPLOY_DEPLOYMENTS,
        RELEASES::STACK => RELEASES::STACK_EVENTS
      }.freeze
      PLATFORM_HISTORIES = { PLATFORMS::APP_RUNNER => PLATFORMS::APP_OPERATIONS, PLATFORMS::BEANSTALK => PLATFORMS::ENVIRONMENT_EVENTS }.freeze
      ROLLBACKS = {
        RELEASES::PIPELINE => RELEASES::ROLLBACK_PIPELINE_STAGE, RELEASES::DEPLOYMENT_GROUP => RELEASES::STOP_CODEDEPLOY_DEPLOYMENT,
        RELEASES::STACK => RELEASES::CANCEL_STACK_UPDATE
      }.freeze
      TOOLS = {
        LOGS => [ SEARCH_LOGS, BUILD_LOG ], METRICS => "cloudwatch_metrics", DEPLOYS => [ DEPLOYMENTS, *PLATFORM_HISTORIES.values ],
        HISTORY => [ DEPLOYMENTS, BUILDS, *HISTORIES.values, *PLATFORM_HISTORIES.values ], STATUS => [ "describe_resource", PLATFORMS::DESCRIBE_APP ],
        ROLLBACK => [ "rollback_deployment", RELEASES::STOP_SERVICE_DEPLOYMENT, *ROLLBACKS.values ], RESTART => "restart_service", SCALE => "scale_service"
      }.freeze
      # Each tool answers one capability for one resource, so an agent holding the capability is not offered it as well.
      # cloudwatch_metrics reads every metric AWS documents for each kind, beyond the ones a capability names, build_log
      # reads any build of a project by its id, and stop_service_deployment and stop_codedeploy_deployment also stop
      # without rolling back, so they stay offered as they are.
      WRAPPED = TOOLS.values.flatten.uniq.excluding(TOOLS[METRICS], BUILD_LOG, RELEASES::STOP_SERVICE_DEPLOYMENT, RELEASES::STOP_CODEDEPLOY_DEPLOYMENT).freeze
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
      # An ECS rollback to a service deployment, by its ARN or its id (the ARN's last part, such as NCWGC2ZR-taawPAYrIaU5
      # in the ECS developer guide), stops that deployment and rolls back to the revision before it. Anything else is a
      # task definition revision, which rollback_deployment takes or refuses as before.
      SERVICE_DEPLOYMENT = /#{PACK::Releases::SERVICE_DEPLOYMENT_ARN.source}|\A(?=[A-Za-z0-9_-]*[A-Za-z])[A-Za-z0-9_-]{16,}\z/

      def self.route(key, resource, given, tool: nil, settings: nil)
        arn = resource.external_id
        platform = PLATFORMS.platform_of(arn)
        return platform_route(key, resource, platform, given) if platform

        case key
        when LOGS then logs(resource, given)
        when METRICS
          names = metric_names(given, METRIC_MAP.fetch(resource.kind), PACK::PROVIDER)
          Route.new(tool_name: TOOLS[METRICS], arguments: { "resource" => arn, "metrics" => names.presence }.compact.merge(given.slice(*RANGE)))
        when DEPLOYS then Route.new(tool_name: DEPLOYMENTS, arguments: { "resource" => arn }.merge(given.slice("limit")))
        when STATUS then Route.new(tool_name: tool_for(STATUS), arguments: { "resource" => arn })
        when HISTORY then history(resource, given)
        when ROLLBACK then rollback(resource, given)
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

      # A pipeline's, deployment group's or stack's own runs, or an ECS service's deployments and a CodeBuild project's
      # builds, one read by its id when the run is named.
      def self.history(resource, given)
        tool = HISTORIES[resource.kind]
        unless tool
          arguments = { "resource" => resource.external_id, "run" => given["run"].to_s.strip.presence, "limit" => Answers.limit(given, History::LIMIT) }.compact
          return Route.new(tool_name: resource.kind == PACK::PROJECT ? BUILDS : DEPLOYMENTS, arguments: arguments, present: RunHistory.presenter(resource.name, given))
        end

        Route.new(tool_name: tool, arguments: { "resource" => resource.external_id, "limit" => Answers.limit(given, History::LIMIT) }.merge(given.slice("run", "name").compact_blank))
      end

      # An ECS service goes back to a task definition revision, or out of a deployment still going by its id. A
      # pipeline's stage goes back to an earlier execution (stage:execution, or the execution alone when one stage
      # deploys), a deployment group's deployment still going is stopped and rolled back, and a stack's update is cancelled.
      def self.rollback(resource, given)
        to = target(given)
        arn = resource.external_id
        case resource.kind
        when RELEASES::PIPELINE
          stage, execution = to.include?(":") ? to.split(":", 2) : [ nil, to ]
          Route.new(tool_name: ROLLBACKS.fetch(resource.kind), arguments: { "resource" => arn, "stage" => stage, "to" => execution }.compact)
        when RELEASES::DEPLOYMENT_GROUP then Route.new(tool_name: ROLLBACKS.fetch(resource.kind), arguments: { "resource" => arn, "deployment" => to, "roll_back" => true })
        when RELEASES::STACK then Route.new(tool_name: ROLLBACKS.fetch(resource.kind), arguments: { "resource" => arn, "operation" => to })
        when PACK::SERVICE
          return Route.new(tool_name: TOOLS[ROLLBACK].first, arguments: { "resource" => arn, "to" => to }) unless to.match?(SERVICE_DEPLOYMENT)

          Route.new(tool_name: RELEASES::STOP_SERVICE_DEPLOYMENT, arguments: { "resource" => arn, "deployment" => to, "mode" => RELEASES::ROLLBACK_MODE })
        else Route.new(tool_name: TOOLS[ROLLBACK].first, arguments: { "resource" => arn, "to" => to })
        end
      end

      # An App Runner service or Elastic Beanstalk environment answers how it stands and what it deployed. Its logs,
      # metrics and changes are refused, naming what reads them instead.
      def self.platform_route(key, resource, platform, given)
        arn = resource.external_id
        name = PLATFORMS::PLATFORM_NAMES.fetch(platform)
        case key
        when STATUS then Route.new(tool_name: PLATFORMS::DESCRIBE_APP, arguments: { "resource" => arn })
        when HISTORY, DEPLOYS
          Route.new(tool_name: PLATFORM_HISTORIES.fetch(platform),
                    arguments: { "resource" => arn, "limit" => Answers.limit(given, History::LIMIT) }.merge(given.slice("run", "name").compact_blank))
        when LOGS
          raise Unroutable, "#{resource.name} is #{article(name)}, whose logs are in CloudWatch Logs under /aws/#{platform}/#{resource.name}. " \
                            "Read them with logs_insights_query."
        else raise Unroutable, "#{resource.name} is #{article(name)}. Firefight reads how it stands and what it deployed, and runs no #{SPECS.fetch(key).what.delete_prefix('a ')} for it."
        end
      end

      def self.article(name) = "#{name.match?(/\A[AEIOU]/) ? 'an' : 'a'} #{name}"
      private_class_method :logs, :history, :rollback, :platform_route, :article
    end
  end
end
