module Integrations
  # Calls to Fly.io's APIs with a workspace's own token, for the Fly.io integration: the Machines API
  # (docs.fly.io/api/machines/openapi.json), the GraphQL API flyctl reads releases from (superfly/fly-go,
  # resource_releases.go), the logs endpoint flyctl polls (docs, monitoring/logs-api-options.mdx) and the org's
  # Prometheus (docs, monitoring/metrics.mdx).
  class FlyApi
    class Error < Integrations::Error; end
    # The machine changed since it was read, so an update guarded by its version was refused (spec, UpdateMachineRequest).
    class Conflict < Error; end

    MACHINES_ROOT = "https://api.machines.dev/v1".freeze
    API_ROOT = "https://api.fly.io".freeze
    PROVIDER = "Fly".freeze
    CONFLICT = 409
    # Fly puts its reason in error as a string (spec, ErrorResponse), which the shared reader would try to dig into.
    REASON = ->(body) { (body["error"] if body["error"].is_a?(String)).presence || body["message"].presence }
    # A token from fly tokens create holds macaroons, which flyctl sends under the FlyV1 scheme, and anything else under
    # Bearer (superfly/fly-go, tokens/tokens.go).
    MACAROON = /(?:\A|,)\s*(?:fm1r|fm1a|fm2)_/
    SCHEME = /\A(?:FlyV1|Bearer)\s+/i
    APPS_PAGE = 1000
    STARTED = "started".freeze
    # Fly waits at most 60 seconds (spec, wait timeout), and a machine that boots slower than this is reported as not up.
    WAIT_SECONDS = 50
    WAIT_MARGIN = 10
    READ_TIMEOUT = 30

    RELEASES_QUERY = <<~GRAPHQL.squish.freeze
      query($appName: String!, $limit: Int!) { app(name: $appName) { releases: releasesUnprocessed(first: $limit) {
      nodes { id version description reason status imageRef stable user { id email name } createdAt } } } }
    GRAPHQL

    def initialize(token)
      @token = token.to_s.strip
    end

    # The Authorization header as flyctl writes it. A pasted scheme is kept, and a macaroon goes under FlyV1.
    def authorization
      return @token if @token.match?(SCHEME)

      @token.match?(MACAROON) ? "FlyV1 #{@token}" : "Bearer #{@token}"
    end

    def apps(org_slug, limit: APPS_PAGE) = Array(machines_get("/apps", "org_slug" => org_slug, "limit" => limit)["apps"])

    def app(app_name) = machines_get("/apps/#{segment(app_name)}")

    def machines(app_name) = Array(machines_get("/apps/#{segment(app_name)}/machines"))

    def certificates(app_name) = Array(machines_get("/apps/#{segment(app_name)}/certificates", "limit" => 500)["certificates"])

    def postgres_clusters(org_slug) = Array(machines_get("/postgres", "org_slug" => org_slug)["data"])

    def postgres_cluster(cluster_id) = machines_get("/postgres/#{segment(cluster_id)}")

    def restart_machine(app_name, machine_id) = machines_post("/apps/#{segment(app_name)}/machines/#{segment(machine_id)}/restart")

    # The whole config goes back with the change, and current_version makes Fly refuse it if the machine moved on.
    def update_machine(app_name, machine_id, config:, current_version:)
      machines_post("/apps/#{segment(app_name)}/machines/#{segment(machine_id)}", "config" => config, "current_version" => current_version)
    end

    # Waits until the machine is started, or at most timeout seconds, and answers whether it got there. version is the
    # machine version an update answered, so an old start does not count (spec, GET .../machines/{machine_id}/wait).
    def wait_started(app_name, machine_id, version: nil, timeout: WAIT_SECONDS)
      uri = URI.parse("#{MACHINES_ROOT}/apps/#{segment(app_name)}/machines/#{segment(machine_id)}/wait")
      answer = get(uri, { "state" => STARTED, "version" => version, "timeout" => timeout }, read_timeout: timeout + WAIT_MARGIN)
      answer["ok"] != false && answer["state"].to_s.in?([ "", STARTED ])
    end

    def releases(app_name, limit:)
      data = graphql(RELEASES_QUERY, "appName" => app_name, "limit" => limit)
      Array(data.dig("app", "releases", "nodes"))
    end

    # One page of log lines from next_token on, a nanosecond time, oldest first. Fly calls this endpoint not officially
    # supported but stable, since flyctl depends on it.
    def logs(app_name, next_token:)
      get(URI.parse("#{API_ROOT}/api/v1/apps/#{segment(app_name)}/logs"), { "next_token" => next_token })
    end

    # A Prometheus range query over the org's metrics, answered in Prometheus's own shape.
    def query_range(org_slug, query:, start:, finish:, step:)
      answer = get(URI.parse("#{API_ROOT}/prometheus/#{segment(org_slug)}/api/v1/query_range"),
                   { "query" => query, "start" => start.to_i, "end" => finish.to_i, "step" => step.to_i })
      raise Error, "Fly's metrics answered #{answer['errorType']}: #{answer['error']}" if answer["status"] == "error"

      Array(answer.dig("data", "result"))
    end

    private

    def machines_get(path, query = {}) = get(URI.parse("#{MACHINES_ROOT}#{path}"), query)

    def machines_post(path, body = nil)
      uri = URI.parse("#{MACHINES_ROOT}#{path}")
      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/json"
      request.body = (body || {}).to_json
      send_request(uri, request)
    end

    def graphql(query, variables)
      uri = URI.parse("#{API_ROOT}/graphql")
      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/json"
      request.body = { query: query, variables: variables }.to_json
      answer = send_request(uri, request)
      errors = Array(answer["errors"]).filter_map { |error| error["message"] }
      raise Error, "Fly answered: #{errors.join('. ')}" if errors.any? && answer["data"].blank?

      answer["data"] || {}
    end

    def get(uri, query, read_timeout: READ_TIMEOUT)
      uri.query = URI.encode_www_form(query.compact) if query.compact.any?
      send_request(uri, Net::HTTP::Get.new(uri), read_timeout: read_timeout)
    end

    def send_request(uri, request, read_timeout: READ_TIMEOUT)
      request["Authorization"] = authorization
      request["Accept"] = "application/json"
      Http.json(uri, request, error_class: Error, provider_name: PROVIDER, reason: REASON, read_timeout: read_timeout,
                              refine: ->(code, _reason) { Conflict if code == CONFLICT })
    end

    def segment(value) = Http.segment(value)
  end
end
