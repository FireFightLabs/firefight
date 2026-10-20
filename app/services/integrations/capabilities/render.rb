module Integrations
  module Capabilities
    # Render's own tools answer every capability as they are, by the resource's Render id. The change tools call the
    # restart, rollback and scale endpoints in Render's OpenAPI spec.
    module Render
      extend Adapter

      PACK = Packs::Render
      RUNNING = [ ResourceMap::KIND_SERVICE, ResourceMap::KIND_JOB, ResourceMap::KIND_DATABASE ].freeze
      DEPLOYED = [ ResourceMap::KIND_SERVICE, ResourceMap::KIND_JOB, ResourceMap::KIND_SITE ].freeze
      SUPPORTS = {
        LOGS => [ *RUNNING, ResourceMap::KIND_SITE, ResourceMap::KIND_WORKFLOW ], METRICS => [ *RUNNING, ResourceMap::KIND_SITE ],
        DEPLOYS => DEPLOYED, HISTORY => [ *DEPLOYED, ResourceMap::KIND_WORKFLOW ],
        STATUS => [ *RUNNING, ResourceMap::KIND_SITE, ResourceMap::KIND_WORKFLOW ], ROLLBACK => DEPLOYED,
        RESTART => [ ResourceMap::KIND_SERVICE, ResourceMap::KIND_DATABASE ], SCALE => [ ResourceMap::KIND_SERVICE ]
      }.freeze
      DEPLOY_HISTORY = "deploy_history".freeze
      HISTORIES = [ DEPLOY_HISTORY, PACK::Runs::CRON_RUNS, PACK::Runs::JOB_RUNS, PACK::Runs::TASK_RUNS ].freeze
      TOOLS = {
        LOGS => "search_logs", METRICS => "query_metrics", DEPLOYS => "list_deployments", STATUS => "describe_resource",
        HISTORY => HISTORIES, ROLLBACK => "rollback_deploy", RESTART => "restart_service", SCALE => "scale_service"
      }.freeze
      WRAPPED = TOOLS.values.flatten.freeze
      STREAMS = { STREAM_APP => "app", "build" => "build", "requests" => "request" }.freeze
      METRIC_MAP = { "cpu" => "cpu", "memory" => "memory", "requests" => "requests", "http_4xx" => "http_4xx", "http_5xx" => "http_5xx",
                     "tcp_connections" => "active_connections", "latency_p95" => "latency_p95", "disk" => "disk", "bandwidth" => "bandwidth" }.freeze
      # A run named by a one-off job's id is one, whatever the history was asked for (spec, jobId, job- followed by 20
      # characters), and a history asked for by kind reads deploys or one-off jobs when the kind says so.
      JOB_ID = /\Ajob-[0-9a-z]+\z/
      DEPLOY_WORDS = /deploy|build/i
      JOB_WORDS = /job/i

      def self.route(key, resource, given, tool: nil, settings: nil)
        id = resource.external_id
        case key
        when LOGS then Route.new(tool_name: TOOLS[LOGS], arguments: { "resource" => id, "type" => stream(given) }.compact.merge(logs(given)))
        when METRICS
          names = metric_names(given, METRIC_MAP, PACK::PROVIDER)
          Route.new(tool_name: TOOLS[METRICS], arguments: { "resource" => id, "metrics" => names.presence }.compact.merge(given.slice("minutes", "start", "end")))
        when DEPLOYS then Route.new(tool_name: TOOLS[DEPLOYS], arguments: { "resource" => id }.merge(given.slice("limit")))
        when STATUS then Route.new(tool_name: TOOLS[STATUS], arguments: { "resource" => id })
        when HISTORY then Route.new(tool_name: history_tool(resource, given), arguments: { "resource" => id }.merge(given.slice("name", "run", "limit").compact_blank))
        when ROLLBACK then Route.new(tool_name: TOOLS[ROLLBACK], arguments: { "resource" => id, "deploy" => target(given) })
        when RESTART then Route.new(tool_name: TOOLS[RESTART], arguments: { "resource" => id })
        when SCALE then Route.new(tool_name: TOOLS[SCALE], arguments: { "resource" => id, "instances" => instances(given) })
        end
      end

      # A workflow's runs are its task runs and a cron job's its scheduled runs, unless deploys or builds are asked for. A
      # service's are its deploys, unless one-off jobs are asked for or the run named is one.
      def self.history_tool(resource, given)
        name = given["name"].to_s
        return PACK::Runs::TASK_RUNS if resource.kind == ResourceMap::KIND_WORKFLOW
        return PACK::Runs::JOB_RUNS if given["run"].to_s.strip.match?(JOB_ID) || (name.match?(JOB_WORDS) && resource.kind != ResourceMap::KIND_JOB)
        return PACK::Runs::CRON_RUNS if resource.kind == ResourceMap::KIND_JOB && !name.match?(DEPLOY_WORDS)

        DEPLOY_HISTORY
      end

      def self.stream(given)
        asked = given["stream"].presence
        return nil unless asked
        return STREAMS[asked] if STREAMS.key?(asked)

        raise Unroutable, "Render keeps app, build and request logs, so stream must be #{STREAMS.keys.join(', ')}."
      end

      # Render's log search takes text and a regular expression, and has no way to leave lines out.
      def self.logs(given)
        raise Unroutable, "Render's log search cannot leave lines out, so search by text or regex instead of exclude." if given["exclude"].present?

        deploy = { "deploy" => given["deployment"] } if given["stream"] == STREAM_BUILD && given["deployment"].present?
        given.slice("text", "regex", "limit", "minutes", "start", "end").merge(deploy.to_h)
      end
      private_class_method :history_tool, :stream, :logs
    end
  end
end
