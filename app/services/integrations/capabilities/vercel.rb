module Integrations
  module Capabilities
    # Vercel's own tools answer logs, deploys, status and rollback for a project, by its Vercel id. Vercel documents no
    # metrics, restart or scaling in its REST API (openapi.vercel.sh), so those are not offered. Runtime logs are only
    # streamed live by Vercel, so a time range cannot be asked of them.
    module Vercel
      extend Adapter

      PACK = Packs::Vercel
      PROJECT = [ ResourceMap::KIND_SITE ].freeze
      SUPPORTS = { LOGS => PROJECT, DEPLOYS => PROJECT, STATUS => PROJECT, HISTORY => PROJECT, ROLLBACK => PROJECT }.freeze
      TOOLS = {
        LOGS => "deployment_logs", DEPLOYS => "list_deployments", STATUS => "describe_resource", HISTORY => "deploy_history",
        ROLLBACK => "rollback_deployment"
      }.freeze
      # deployment_logs reads any deployment, which the capability cannot name, so it stays offered as it is.
      WRAPPED = TOOLS.values.excluding(TOOLS[LOGS]).freeze
      STREAMS = { STREAM_APP => PACK::RUNTIME, STREAM_BUILD => PACK::BUILD }.freeze

      def self.route(key, resource, given, tool: nil, settings: nil)
        id = resource.external_id
        case key
        when LOGS then Route.new(tool_name: TOOLS[LOGS], arguments: { "resource" => id, "type" => stream(given) }.merge(logs(given)))
        when DEPLOYS then Route.new(tool_name: TOOLS[DEPLOYS], arguments: { "resource" => id }.merge(given.slice("limit")))
        when STATUS then Route.new(tool_name: TOOLS[STATUS], arguments: { "resource" => id })
        when HISTORY then Route.new(tool_name: TOOLS[HISTORY], arguments: { "resource" => id }.merge(given.slice("name", "limit")))
        when ROLLBACK then Route.new(tool_name: TOOLS[ROLLBACK], arguments: { "resource" => id, "deployment" => target(given) })
        end
      end

      def self.stream(given)
        asked = given["stream"].presence || STREAM_APP
        STREAMS.fetch(asked) { raise Unroutable, "Vercel keeps what functions log and build output, so stream must be #{STREAMS.keys.join(' or ')}." }
      end

      # Vercel's log tool filters by text and leaves text out. It has no regular expressions.
      def self.logs(given)
        raise Unroutable, "Vercel's logs cannot be searched by a regular expression, so give text instead." if given["regex"].present?

        given.slice("text", "exclude", "limit")
      end
      private_class_method :stream, :logs
    end
  end
end
