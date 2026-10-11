module Integrations
  module Capabilities
    # Northflank's own tools answer most capabilities as they are, by the resource's Northflank id. A rollback, restart or
    # scale goes through api_request with the paths its fixes skill gives.
    module Northflank
      extend Adapter

      RUNNING = [ ResourceMap::KIND_SERVICE, ResourceMap::KIND_DATABASE, ResourceMap::KIND_JOB ].freeze
      SUPPORTS = {
        LOGS => [ *RUNNING, ResourceMap::KIND_BUILD_SERVICE ], METRICS => RUNNING, DEPLOYS => [ ResourceMap::KIND_SERVICE ],
        STATUS => RUNNING,
        HISTORY => [ *RUNNING, ResourceMap::KIND_BUILD_SERVICE, ResourceMap::KIND_WORKFLOW, ResourceMap::KIND_RELEASE_FLOW ],
        ROLLBACK => [ ResourceMap::KIND_SERVICE ], RESTART => [ ResourceMap::KIND_SERVICE, ResourceMap::KIND_DATABASE ],
        SCALE => RUNNING
      }.freeze
      API = "api_request".freeze
      BUILD_HISTORY = "build_history".freeze
      JOB_RUNS = "job_runs".freeze
      HISTORIES = {
        ResourceMap::KIND_WORKFLOW => "workflow_runs", ResourceMap::KIND_RELEASE_FLOW => "release_flow_runs",
        ResourceMap::KIND_JOB => JOB_RUNS, ResourceMap::KIND_DATABASE => "backup_history"
      }.freeze
      TOOLS = {
        LOGS => "search_logs", METRICS => "query_metrics", DEPLOYS => "list_deployments", STATUS => "describe_resource",
        HISTORY => [ BUILD_HISTORY, *HISTORIES.values ], ROLLBACK => API, RESTART => API, SCALE => API
      }.freeze
      # job_runs keeps being offered as it is, since its text says more of each run than run history does.
      WRAPPED = TOOLS.values.flatten.uniq.excluding(API, JOB_RUNS).freeze
      STREAMS = { "app" => "runtime", "build" => "build", "requests" => "ingress", "internal" => "mesh", "cdn" => "cdn", "backup" => "backup", "restore" => "restore" }.freeze
      METRIC_MAP = {
        "cpu" => "cpu", "memory" => "memory", "requests" => "requests", "http_4xx" => "http4xxResponses",
        "http_5xx" => "http5xxResponses", "network_in" => "networkIngress", "network_out" => "networkEgress",
        "tcp_connections" => "tcpConnectionsOpen", "disk" => "diskUsage", "bandwidth" => "bandwidth"
      }.freeze
      PASSED = %w[text regex exclude limit minutes start end run].freeze
      KIND_PATHS = { ResourceMap::KIND_SERVICE => "services", ResourceMap::KIND_DATABASE => "addons", ResourceMap::KIND_JOB => "jobs" }.freeze
      # A deployment's own id (ListServiceDeploymentsResult, "6560a1b2c3d4e5f6a7b8c9d0"), which only ending a canary
      # rollout takes. A build's id is words and a number, and an image has a registry path.
      DEPLOYMENT_ID = /\A\h{24}\z/
      # A job runs one container a run, so it is scaled by its plan alone.
      ONE_RUN = 1

      def self.takes_plan? = true

      def self.logs_by_run? = true

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
        when HISTORY then history(resource, given)
        when ROLLBACK then rollback(resource, given)
        when RESTART then change("#{KIND_PATHS.fetch(resource.kind)}/#{id}/restart")
        when SCALE then scale(resource, given)
        end
      end

      # A workflow's or release flow's runs with their nodes, a job's runs, a database's backups, and a service's builds,
      # each read by its id when the run is named. A service that runs another's builds has none of its own, so its
      # history is the builds of the one that builds it.
      def self.history(resource, given)
        passed = given.slice("name", "run", "limit").compact_blank
        case resource.kind
        when ResourceMap::KIND_WORKFLOW then Route.new(tool_name: HISTORIES.fetch(resource.kind), arguments: { "workflow" => resource.external_id }.merge(passed))
        when ResourceMap::KIND_RELEASE_FLOW
          pipeline, stage = resource.external_id.split("/", 2)
          Route.new(tool_name: HISTORIES.fetch(resource.kind),
                    arguments: { "pipeline" => pipeline, "stage" => stage.to_s.capitalize }.merge(passed))
        when ResourceMap::KIND_JOB
          Route.new(tool_name: JOB_RUNS, arguments: { "job" => resource.external_id }.merge(passed), present: RunHistory.presenter(resource.name, given))
        when ResourceMap::KIND_DATABASE then Route.new(tool_name: HISTORIES.fetch(resource.kind), arguments: { "resource" => resource.external_id }.merge(passed))
        else Route.new(tool_name: BUILD_HISTORY, arguments: { "resource" => builder_of(resource) }.merge(passed))
        end
      end

      # Back to an earlier build for a service that deploys builds, to an earlier image for one that deploys an image, and
      # out of an active canary rollout to an earlier deployment (rollout/rollback), each as Northflank's API takes it.
      def self.rollback(resource, given)
        to = target(given)
        id = resource.external_id
        return change("services/#{id}/rollout/rollback", { "deployment" => to }) if to.match?(DEPLOYMENT_ID)

        image = resource.details.to_h[Packs::Northflank::MapReading::IMAGE]
        return change("services/#{id}/deployment", { "internal" => { "id" => builder_of(resource), "buildId" => to } }) if image.blank?

        credentials = resource.details.to_h[Packs::Northflank::MapReading::IMAGE_CREDENTIALS]
        change("services/#{id}/deployment", { "external" => { "imagePath" => to, "credentials" => credentials.presence }.compact })
      end

      # A service's instances, a database's replicas and a job's plan, with the plan passed for any of them. With a plan,
      # instances may be left out to keep the count.
      def self.scale(resource, given)
        plan = given[PLAN_ARG].to_s.strip.presence
        id = resource.external_id
        count = instances(given) if given["instances"].present? || plan.nil?
        case resource.kind
        when ResourceMap::KIND_DATABASE then change("addons/#{id}/scale", { "replicas" => count, "deploymentPlan" => plan }.compact)
        when ResourceMap::KIND_JOB
          raise Unroutable, "A Northflank job runs one container a run, so instances must be #{ONE_RUN}. Name its plan to give it more." unless count.nil? || count == ONE_RUN
          raise Unroutable, "A Northflank job is scaled by its plan. Name the plan, such as nf-compute-20." unless plan

          change("jobs/#{id}/scale", { "deploymentPlan" => plan })
        else change("services/#{id}/scale", { "instances" => count, "deploymentPlan" => plan }.compact)
        end
      end

      def self.change(path, body = nil) = Route.new(tool_name: API, arguments: { "method" => "POST", "path" => path, "body" => body }.compact)

      # The service whose builds a rollback deploys: the build service it runs builds of, or itself when it builds its own.
      def self.builder_of(resource)
        return resource.external_id unless resource.kind == ResourceMap::KIND_SERVICE

        built = ResourceMap::Link.facts.where(from_resource: resource, relation: ResourceMap::RELATION_RUNS_BUILDS_OF, origin: ResourceMap::ORIGIN_DECLARED)
                                 .joins(:to_resource).merge(ResourceMap::Resource.present).order(:created_at).first&.to_resource
        built&.external_id || resource.external_id
      end
      private_class_method :change, :builder_of, :history, :rollback, :scale
    end
  end
end
