module Integrations
  module Capabilities
    # Convex answers through its pack's own tools, one connection per deployment, so a request needs no id of its own.
    # Logs are the functions' own (the only stream Convex keeps), errors are the executions that failed, deploys are the
    # pushes its audit log records, and status is who the deployment is and whether it runs. Convex documents no metrics
    # series and no rollback, restart or scale, so those are not offered.
    module Convex
      extend Adapter

      PACK = Packs::Convex
      SUPPORTS = {
        LOGS => [ ResourceMap::KIND_SERVICE ], ERRORS => [ ResourceMap::KIND_SERVICE ],
        DEPLOYS => [ ResourceMap::KIND_SERVICE ], STATUS => [ ResourceMap::KIND_SERVICE ]
      }.freeze
      TOOLS = { LOGS => "search_logs", ERRORS => "function_errors", DEPLOYS => "recent_pushes", STATUS => "deployment_status" }.freeze
      WRAPPED = TOOLS.values.freeze
      RANGE_ARGS = %w[minutes start end].freeze

      def self.route(key, _resource, given, tool: nil, settings: nil)
        case key
        when LOGS
          raise Unroutable, "Convex keeps only what its functions print, so stream must be #{STREAM_APP}." unless given["stream"].in?([ nil, "", STREAM_APP ])
          raise Unroutable, "Convex logs are searched by text, not by a regular expression. Give text instead." if given["regex"].present?

          Route.new(tool_name: TOOLS[LOGS], arguments: given.slice("text", "exclude", "limit", *RANGE_ARGS))
        when ERRORS then Route.new(tool_name: TOOLS[ERRORS], arguments: given.slice("text", "limit", *RANGE_ARGS))
        when DEPLOYS then Route.new(tool_name: TOOLS[DEPLOYS], arguments: given.slice("limit"))
        when STATUS then Route.new(tool_name: TOOLS[STATUS], arguments: {})
        end
      end
    end
  end
end
