module Integrations
  module Capabilities
    # Google Cloud's pack answers every capability with a tool of its own, by the resource's id on the map. Its metrics
    # already take the names every capability uses, so only the ones Google keeps for each kind of resource are passed
    # on (Packs::GoogleCloud::Metrics). Revisions, errors, a rollback and scaling are Cloud Run's, and a restart is
    # Cloud SQL's or a Compute Engine instance's, since Cloud Run has none. Run history is a Cloud Run service's
    # revisions, each from when it was made to when it became ready or failed, or the Cloud Build builds of the trigger
    # that deploys it, when the history asked for is builds or the run is a build's id, a Cloud Run job's executions with
    # their tasks, and a Cloud Deploy pipeline's or stage's rollouts with their jobs, whose logs are read per run. A stage
    # rolls back through Cloud Deploy's own rollback, to a release.
    module GoogleCloud
      extend Adapter

      SERVICE = ResourceMap::KIND_SERVICE
      DATABASE = ResourceMap::KIND_DATABASE
      MACHINE = ResourceMap::KIND_VIRTUAL_MACHINE
      CLUSTER = ResourceMap::KIND_CLUSTER
      JOB = ResourceMap::KIND_JOB
      PIPELINE = ResourceMap::KIND_PIPELINE
      STAGE = ResourceMap::KIND_RELEASE_FLOW
      RELEASES = [ JOB, PIPELINE, STAGE ].freeze
      SUPPORTS = {
        LOGS => [ SERVICE, DATABASE, MACHINE, CLUSTER, *RELEASES ], METRICS => [ SERVICE, DATABASE, MACHINE ], DEPLOYS => [ SERVICE, PIPELINE, STAGE ],
        HISTORY => [ SERVICE, *RELEASES ], STATUS => [ SERVICE, DATABASE, MACHINE, CLUSTER, *RELEASES ], ERRORS => [ SERVICE ],
        ROLLBACK => [ SERVICE, STAGE ], RESTART => [ DATABASE, MACHINE ], SCALE => [ SERVICE ]
      }.freeze
      REVISIONS = "list_revisions".freeze
      BUILDS = "list_builds".freeze
      EXECUTIONS = "list_executions".freeze
      ROLLOUTS = "list_rollouts".freeze
      ROLLBACK_TARGET = "rollback_target".freeze
      TOOLS = {
        LOGS => "search_logs", METRICS => "query_metrics", DEPLOYS => [ REVISIONS, ROLLOUTS ], HISTORY => [ REVISIONS, BUILDS, EXECUTIONS, ROLLOUTS ],
        STATUS => "describe_resource", ERRORS => "error_groups", ROLLBACK => [ "rollback_service", ROLLBACK_TARGET ], RESTART => "restart_resource",
        SCALE => "scale_service"
      }.freeze
      # Every tool, the changes too, is answered one to one, so Halon is offered the capability and never the tool as well.
      # list_builds also reads a region's builds that deploy no service, so it stays offered.
      WRAPPED = (TOOLS.values.flatten.uniq - [ BUILDS ]).freeze
      PASSED = %w[text regex exclude stream limit minutes start end].freeze
      BUILD_NAME = /build/i

      # A restart reaches only some kinds, so the details say which.
      def self.phrase(key) = key == RESTART ? "restart a Cloud SQL database or a virtual machine" : super

      # A Cloud Run job's executions and a Cloud Deploy rollout keep their logs per run.
      def self.logs_by_run? = true

      def self.route(key, resource, given, tool: nil, settings: nil)
        return release_route(key, resource, given) if RELEASES.include?(resource.kind)
        raise Unroutable, "Google Cloud keeps logs per run for Cloud Run jobs and Cloud Deploy rollouts, so leave run out for #{resource.name}." if key == LOGS && given[RUN_ARG].present?

        id = resource.external_id
        case key
        when LOGS then Route.new(tool_name: TOOLS[LOGS], arguments: { "resource" => id }.merge(given.slice(*PASSED)).merge(build_of(given)))
        when METRICS
          names = metric_names(given, Packs::GoogleCloud::Metrics.names(resource.kind), Packs::GoogleCloud::PROVIDER)
          Route.new(tool_name: TOOLS[METRICS], arguments: { "resource" => id, "metrics" => names.presence }.compact.merge(given.slice("minutes", "start", "end")))
        when DEPLOYS then Route.new(tool_name: REVISIONS, arguments: { "resource" => id }.merge(given.slice("limit")))
        when STATUS then Route.new(tool_name: TOOLS[STATUS], arguments: { "resource" => id })
        when HISTORY then history(resource, given)
        when ERRORS then Route.new(tool_name: TOOLS[ERRORS], arguments: { "resource" => id }.merge(given.slice("text", "limit", "minutes", "start", "end")))
        when ROLLBACK then Route.new(tool_name: tool_for(ROLLBACK), arguments: { "resource" => id, "revision" => target(given) })
        when RESTART then Route.new(tool_name: TOOLS[RESTART], arguments: { "resource" => id })
        when SCALE then Route.new(tool_name: TOOLS[SCALE], arguments: { "resource" => id, "min_instances" => instances(given) })
        end
      end

      # A build's id, or a history named for builds, reads the service's builds. Anything else is its revisions, one by
      # its name when a run is given.
      def self.history(resource, given)
        run = given["run"].to_s.strip.presence
        limit = Answers.limit(given, History::LIMIT)
        if run&.match?(Packs::GoogleCloud::BUILD_ID) || (run.nil? && given["name"].to_s.match?(BUILD_NAME))
          return Route.new(tool_name: BUILDS, arguments: { "resource" => resource.external_id, "build" => run, "limit" => limit }.compact)
        end

        Route.new(tool_name: REVISIONS, arguments: { "resource" => resource.external_id, "revision" => run, "limit" => limit }.compact,
                  present: RunHistory.presenter(resource.name, given))
      end

      # The build stream reads one build's log when the deployment named is a build's id, such as the one a watch follows.
      def self.build_of(given)
        deployment = given["deployment"].to_s.strip
        given["stream"] == STREAM_BUILD && deployment.match?(Packs::GoogleCloud::BUILD_ID) ? { "build" => deployment } : {}
      end
      private_class_method :history, :build_of

      # A job's executions, and a pipeline's or stage's rollouts, each read by its id when the run is named, its logs
      # narrowed to a run, and a stage rolled back to a release.
      def self.release_route(key, resource, given)
        id = resource.external_id
        case key
        when LOGS then Route.new(tool_name: TOOLS[LOGS], arguments: { "resource" => id }.merge(given.slice(*PASSED, RUN_ARG)))
        when DEPLOYS then Route.new(tool_name: ROLLOUTS, arguments: { "resource" => id }.merge(given.slice("limit")))
        when STATUS then Route.new(tool_name: TOOLS[STATUS], arguments: { "resource" => id })
        when HISTORY
          passed = { "resource" => id, "run" => given["run"].to_s.strip.presence, "limit" => Answers.limit(given, History::LIMIT) }.compact
          return Route.new(tool_name: EXECUTIONS, arguments: passed) if resource.kind == JOB

          Route.new(tool_name: ROLLOUTS, arguments: passed.merge({ "name" => given["name"].presence }.compact))
        when ROLLBACK then Route.new(tool_name: ROLLBACK_TARGET, arguments: { "resource" => id, "release" => target(given) })
        end
      end
      private_class_method :release_route
    end
  end
end
