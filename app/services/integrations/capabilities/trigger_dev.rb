module Integrations
  module Capabilities
    # Trigger.dev's own tools answer for a task on the map, by its identifier. Deployments and their rollback belong to the
    # environment, not to one task, so recent_deploys lists the environment's versions and a rollback promotes one for
    # every task in it. Trigger.dev keeps only what a task logs, so stream must be app.
    module TriggerDev
      extend Adapter

      TASKS = [ ResourceMap::KIND_JOB ].freeze
      SUPPORTS = {
        LOGS => TASKS, METRICS => TASKS, DEPLOYS => TASKS, STATUS => TASKS, ERRORS => TASKS, ROLLBACK => TASKS
      }.freeze
      TOOLS = {
        LOGS => "search_task_logs", METRICS => "task_metrics", DEPLOYS => "list_deployments", STATUS => "describe_task",
        ERRORS => "list_errors", ROLLBACK => "promote_deployment"
      }.freeze
      WRAPPED = TOOLS.values.freeze
      # The capability's metric names Trigger.dev keeps for a task, by the same names in its pack.
      METRIC_MAP = Packs::TriggerDev::METRICS.index_with(&:itself).freeze
      PASSED = %w[text regex exclude limit minutes start end].freeze
      TASK = "task".freeze

      def self.route(key, resource, given, tool: nil, settings: nil)
        task = { TASK => resource.external_id }
        case key
        when LOGS
          stream = given["stream"].presence
          raise Unroutable, "Trigger.dev keeps only what a task logs, so stream must be #{STREAM_APP}." if stream && stream != STREAM_APP

          Route.new(tool_name: TOOLS[LOGS], arguments: task.merge(given.slice(*PASSED)))
        when METRICS
          names = metric_names(given, METRIC_MAP, Packs::TriggerDev::PROVIDER)
          Route.new(tool_name: TOOLS[METRICS], arguments: task.merge("metrics" => names.presence).compact.merge(given.slice("minutes", "start", "end")))
        when DEPLOYS then Route.new(tool_name: TOOLS[DEPLOYS], arguments: given.slice("limit"))
        when STATUS then Route.new(tool_name: TOOLS[STATUS], arguments: task)
        when ERRORS then Route.new(tool_name: TOOLS[ERRORS], arguments: task.merge(given.slice("text", "limit", "minutes", "start", "end")))
        when ROLLBACK then Route.new(tool_name: TOOLS[ROLLBACK], arguments: { "version" => target(given) })
        end
      end
    end
  end
end
