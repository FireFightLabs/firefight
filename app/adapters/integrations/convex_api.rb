module Integrations
  # Calls to one Convex deployment with the deploy key a workspace pastes, for the Convex integration: reads, pausing and
  # unpausing the deployment, and the webhook log stream live updates use. The Deployment API's paths and answers are
  # from Convex's published spec (get-convex/convex-backend,
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
    WEBHOOK_STREAM = "webhook".freeze
    # One JSON array of events a request (WebhookFormat).
    WEBHOOK_FORMAT = "json".freeze

    def initialize(deployment_url, deploy_key)
      @root = deployment_url.to_s.chomp("/")
      @key = deploy_key
    end

    # Who the deployment is: its team, project, id and type, or kind selfHosted.
    def deployment_info = get("#{API_PREFIX}/deployment_info")

    def canonical_urls = get("#{API_PREFIX}/get_canonical_urls")

    # The deployment's environment variables, name to value (ListEnvVarsResponse). Convex says a later version may leave
    # its secret ones out.
    def environment_variables = get("#{API_PREFIX}/list_environment_variables")["environmentVariables"].to_h

    # One page of audit log events on or after from (milliseconds since epoch), least recent first, with the cursor for
    # the next page.
    def audit_log(from:, limit: AUDIT_PAGE, cursor: nil)
      get("#{API_PREFIX}/list_audit_log_events", { "from" => from, "limit" => limit, "cursor" => cursor })
    end

    # The function executions the deployment still keeps after cursor (milliseconds), and the cursor to read on from.
    def function_logs(cursor:) = get(LOGS_PATH, { "cursor" => cursor })

    # Each metric's usage in the current UTC day and month, by the names usage limits use, and how complete it is
    # (GetCurrentUsageResponse).
    def current_usage = get("#{API_PREFIX}/get_current_usage")

    # The deployment's usage limits, each a warning or a stop once a metric passes it in a day or a month.
    def usage_limits = Array(get("#{API_PREFIX}/list_usage_limits")["usageLimits"])

    # Function calls fail while paused, scheduled jobs wait and crons are skipped, until unpaused.
    def pause = post("#{API_PREFIX}/pause_deployment")

    def unpause = post("#{API_PREFIX}/unpause_deployment")

    # Every log stream the deployment sends to, of any kind (LogStreamConfig). Convex allows one of each kind.
    def log_streams = Array(get("#{API_PREFIX}/list_log_streams"))

    # A webhook log stream sending only these topics, answering its id and the secret it signs with.
    def create_webhook_stream(url:, topics:)
      post("#{API_PREFIX}/create_log_stream", { "logStreamType" => WEBHOOK_STREAM, "url" => url, "format" => WEBHOOK_FORMAT, "topics" => topics })
    end

    def delete_log_stream(id) = post("#{API_PREFIX}/delete_log_stream/#{Http.segment(id)}")

    private

    def get(path, query = {})
      uri = URI.parse("#{@root}#{path}")
      uri.query = URI.encode_www_form(query.compact) if query.compact.any?
      request = Net::HTTP::Get.new(uri)
      send_request(uri, request)
    end

    def post(path, body = nil)
      uri = URI.parse("#{@root}#{path}")
      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/json"
      request.body = (body || {}).to_json
      send_request(uri, request)
    end

    def send_request(uri, request)
      request["Authorization"] = "Convex #{@key}"
      Http.json(uri, request, error_class: Error, provider_name: "Convex", reason: REASON)
    rescue Error => error
      raise unless error.message.match?(REFUSED)

      raise Error, Sentence.join(Sentence.clean(error), nil, after: "Check that the deploy key belongs to this deployment and has not been revoked")
    end
  end
end
