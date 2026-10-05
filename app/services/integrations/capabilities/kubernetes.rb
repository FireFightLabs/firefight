module Integrations
  module Capabilities
    # The Kubernetes pack's own tools answer every capability, given the workload's namespace and kind/name, which the
    # map's id holds as namespace/kind/name. Metrics are cpu and memory as they are now, the only two that metrics.k8s.io
    # PodMetrics keeps.
    module Kubernetes
      extend Adapter

      SUPPORTS = {
        LOGS => [ ResourceMap::KIND_SERVICE, ResourceMap::KIND_JOB ], METRICS => [ ResourceMap::KIND_SERVICE ],
        DEPLOYS => [ ResourceMap::KIND_SERVICE ], STATUS => [ ResourceMap::KIND_SERVICE, ResourceMap::KIND_JOB ],
        ROLLBACK => [ ResourceMap::KIND_SERVICE ], RESTART => [ ResourceMap::KIND_SERVICE ], SCALE => [ ResourceMap::KIND_SERVICE ]
      }.freeze
      TOOLS = {
        LOGS => "workload_logs", METRICS => "pod_metrics", DEPLOYS => "rollout_history", STATUS => "describe_workload",
        ROLLBACK => "rollout_undo", RESTART => "rollout_restart", SCALE => "scale_workload"
      }.freeze
      # workload_logs also reads one pod, or each container before its last restart, which search_logs does not ask, so
      # it stays offered.
      WRAPPED = (TOOLS.values - [ TOOLS[LOGS] ]).freeze
      METRIC_MAP = { "cpu" => "cpu", "memory" => "memory" }.freeze
      PASSED = %w[text regex exclude limit minutes start end].freeze

      def self.route(key, resource, given, tool: nil, settings: nil)
        namespace, kind, name = resource.external_id.split("/", 3)
        workload = { "namespace" => namespace, "resource" => "#{kind}/#{name}" }
        case key
        when LOGS
          unless given["stream"].in?([ nil, "", STREAM_APP ])
            raise Unroutable, "Kubernetes keeps what a container prints, so stream must be #{STREAM_APP}."
          end

          Route.new(tool_name: TOOLS[LOGS], arguments: workload.merge(given.slice(*PASSED)))
        when METRICS
          metric_names(given, METRIC_MAP, "Kubernetes")
          Route.new(tool_name: TOOLS[METRICS], arguments: workload)
        when DEPLOYS then Route.new(tool_name: TOOLS[DEPLOYS], arguments: workload.merge(given.slice("limit")))
        when STATUS then Route.new(tool_name: TOOLS[STATUS], arguments: workload)
        when ROLLBACK then Route.new(tool_name: TOOLS[ROLLBACK], arguments: workload.merge("revision" => revision(given)))
        when RESTART then Route.new(tool_name: TOOLS[RESTART], arguments: workload)
        when SCALE
          raise Unroutable, "#{name} is a daemonset, which runs one pod per node and cannot be scaled." if kind == Packs::Kubernetes::DAEMONSET

          Route.new(tool_name: TOOLS[SCALE], arguments: workload.merge("replicas" => instances(given)))
        end
      end

      def self.revision(given)
        number = Integer(target(given), exception: false)
        raise Unroutable, "Say which revision to go back to, by the number recent_deploys shows." unless number&.positive?

        number
      end
      private_class_method :revision
    end
  end
end
