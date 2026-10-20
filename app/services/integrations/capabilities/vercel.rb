module Integrations
  module Capabilities
    # Vercel's own tools answer logs, metrics, deploys, status and rollback for a project, by its Vercel id. Metrics come from
    # Vercel Observability (POST /v2/observability/query), production's unless the tool is asked otherwise. Vercel documents
    # no restart or scaling in its REST API (openapi.vercel.sh), so those are not offered. Runtime logs are only streamed
    # live by Vercel, so a time range cannot be asked of them.
    module Vercel
      extend Adapter

      PACK = Packs::Vercel
      PROJECT = [ ResourceMap::KIND_SITE ].freeze
      SUPPORTS = { LOGS => PROJECT, METRICS => PROJECT, DEPLOYS => PROJECT, STATUS => PROJECT, HISTORY => PROJECT, ROLLBACK => PROJECT }.freeze
      TOOLS = {
        LOGS => "deployment_logs", METRICS => "query_metrics", DEPLOYS => "list_deployments", STATUS => "describe_resource", HISTORY => "deploy_history",
        ROLLBACK => "rollback_deployment"
      }.freeze
      # deployment_logs reads any deployment, and query_metrics previews too, which the capability cannot ask, so both stay
      # offered as they are.
      WRAPPED = TOOLS.values.excluding(TOOLS[LOGS], TOOLS[METRICS]).freeze
      METRIC_MAP = PACK::METRICS.keys.index_with(&:itself).freeze
      STREAMS = { STREAM_APP => PACK::RUNTIME, STREAM_BUILD => PACK::BUILD }.freeze

      def self.route(key, resource, given, tool: nil, settings: nil)
        id = resource.external_id
        case key
        when LOGS then Route.new(tool_name: TOOLS[LOGS], arguments: { "resource" => id, "type" => stream(given) }.merge(logs(given)))
        when METRICS
          names = metric_names(given, METRIC_MAP, PACK::PROVIDER)
          Route.new(tool_name: TOOLS[METRICS], arguments: { "resource" => id, "metrics" => names.presence }.compact.merge(given.slice("minutes", "start", "end")))
        when DEPLOYS then Route.new(tool_name: TOOLS[DEPLOYS], arguments: { "resource" => id }.merge(given.slice("limit")))
        when STATUS then Route.new(tool_name: TOOLS[STATUS], arguments: { "resource" => id })
        when HISTORY then Route.new(tool_name: TOOLS[HISTORY], arguments: { "resource" => id }.merge(given.slice("name", "run", "limit").compact_blank))
        when ROLLBACK then Route.new(tool_name: TOOLS[ROLLBACK], arguments: { "resource" => id, "deployment" => target(given) })
        end
      end

      def self.stream(given)
        asked = given["stream"].presence || STREAM_APP
        STREAMS.fetch(asked) { raise Unroutable, "Vercel keeps what functions log and build output, so stream must be #{STREAMS.keys.join(' or ')}." }
      end

      # Vercel's log tool filters by text and leaves text out. It has no regular expressions. A deployment named is the one
      # read, so a run being followed is read rather than the newest.
      def self.logs(given)
        raise Unroutable, "Vercel's logs cannot be searched by a regular expression, so give text instead." if given["regex"].present?

        given.slice("deployment", "text", "exclude", "limit").compact_blank
      end
      private_class_method :stream, :logs
    end
  end
end
