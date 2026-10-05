module Integrations
  # Calls to one Convex deployment with the deploy key a workspace pastes, for the Convex integration. Every call is a
  # read. The Deployment API's paths and answers are from Convex's published spec (get-convex/convex-backend,
  # npm-packages/@convex-dev/platform/deployment-openapi.json), served under the deployment's own URL at /api/v1. Function
  # logs come from the endpoint Convex's own CLI and its MCP logs tool read (npm-packages/convex/src/cli/lib/logs.ts and
  # mcp/tools/logs.ts), whose answer is described in npm-packages/convex/function-logs-openapi.json. The key goes as
  # "Convex <key>", the way the CLI's deploymentFetch sends it.
  class ConvexApi
    class Error < Integrations::Error; end

    REFUSED = /\AConvex answered 40[13]:/
    # Convex words a refusal in message, or only in code.
    REASON = ->(body) { body["message"] || body["code"] }
    API_PREFIX = "/api/v1".freeze
    LOGS_PATH = "/api/stream_function_logs".freeze
    # Convex caps a page of audit log events at 100.
    AUDIT_PAGE = 100

    def initialize(deployment_url, deploy_key)
      @root = deployment_url.to_s.chomp("/")
      @key = deploy_key
    end

    # Who the deployment is: its team, project, id and type, or kind selfHosted.
    def deployment_info = get("#{API_PREFIX}/deployment_info")

    def canonical_urls = get("#{API_PREFIX}/get_canonical_urls")

    # One page of audit log events on or after from (milliseconds since epoch), least recent first, with the cursor for
    # the next page.
    def audit_log(from:, limit: AUDIT_PAGE, cursor: nil)
      get("#{API_PREFIX}/list_audit_log_events", { "from" => from, "limit" => limit, "cursor" => cursor })
    end

    # The function executions the deployment still keeps after cursor (milliseconds), and the cursor to read on from.
    def function_logs(cursor:) = get(LOGS_PATH, { "cursor" => cursor })

    private

    def get(path, query = {})
      uri = URI.parse("#{@root}#{path}")
      uri.query = URI.encode_www_form(query.compact) if query.compact.any?
      request = Net::HTTP::Get.new(uri)
      request["Authorization"] = "Convex #{@key}"
      Http.json(uri, request, error_class: Error, provider_name: "Convex", reason: REASON)
    rescue Error => error
      raise unless error.message.match?(REFUSED)

      raise Error, Sentence.join(Sentence.clean(error), nil, after: "Check that the deploy key belongs to this deployment and has not been revoked")
    end
  end
end
