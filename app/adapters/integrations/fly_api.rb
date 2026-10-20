module Integrations
  # Calls to Fly.io's APIs with a workspace's own token, for the Fly.io integration: the Machines API
  # (docs.fly.io/api/machines/openapi.json), the GraphQL API flyctl reads releases from (superfly/fly-go,
  # resource_releases.go), the logs endpoint flyctl polls (docs, monitoring/logs-api-options.mdx) and the org's
  # Prometheus (docs, monitoring/metrics.mdx).
  class FlyApi
    class Error < Integrations::Error; end
    # The machine changed since it was read, so an update guarded by its version was refused (spec, UpdateMachineRequest).
    class Conflict < Error; end
    # Fly has no such app or machine (spec, 404 on GET /v1/apps/{app_name}).
    class NotFound < Error
      include Integrations::NotFound
    end

    MACHINES_HOST = "https://api.machines.dev".freeze
    MACHINES_ROOT = "#{MACHINES_HOST}/v1".freeze
    API_ROOT = "https://api.fly.io".freeze
    PROVIDER = "Fly".freeze
    CONFLICT = 409
    REFINED = { CONFLICT => Conflict, 404 => NotFound }.freeze
    # A token from fly tokens create holds macaroons, which flyctl sends under the FlyV1 scheme, and anything else under
    # Bearer (superfly/fly-go, tokens/tokens.go).
    MACAROON = /(?:\A|,)\s*(?:fm1r|fm1a|fm2)_/
    SCHEME = /\A(?:FlyV1|Bearer)\s+/i
    APPS_PAGE = 1000
    APP_PAGES = 5
    CERTIFICATES_PAGE = 500
    CERTIFICATE_PAGES = 5
    STARTED = "started".freeze
    # Fly waits at most 60 seconds (spec, wait timeout), and a machine that boots slower than this is reported as not up.
    WAIT_SECONDS = 50
    WAIT_MARGIN = 10
    READ_TIMEOUT = 30

    # updatedAt is when a release last changed state, so when a complete or failed one ended (superfly/fly-go, schema.graphql,
    # ReleaseUnprocessed).
    RELEASES_QUERY = <<~GRAPHQL.squish.freeze
      query($appName: String!, $limit: Int!) { app(name: $appName) { releases: releasesUnprocessed(first: $limit) {
      nodes { id version description reason status imageRef stable user { id email name } createdAt updatedAt } } } }
    GRAPHQL
    # The same releases a page at a time, from the cursor the last page ended at (schema.graphql, ReleaseUnprocessedConnection
    # and PageInfo), for one release older than the newest few.
    RELEASE_PAGE_QUERY = <<~GRAPHQL.squish.freeze
      query($appName: String!, $limit: Int!, $after: String) { app(name: $appName) { releases: releasesUnprocessed(first: $limit, after: $after) {
      nodes { id version description reason status imageRef stable user { id email name } createdAt updatedAt } pageInfo { hasNextPage endCursor } } } }
    GRAPHQL
    RELEASE_PAGE = 50
    RELEASE_PAGES = 4

    def initialize(token)
      @token = token.to_s.strip
    end

    # The Authorization header as flyctl writes it. A pasted scheme is kept, and a macaroon goes under FlyV1.
    def authorization
      return @token if @token.match?(SCHEME)

      @token.match?(MACAROON) ? "FlyV1 #{@token}" : "Bearer #{@token}"
    end

    def apps(org_slug, limit: APPS_PAGE) = Array(machines_get("/apps", "org_slug" => org_slug, "limit" => limit)["apps"])

    # Every app in the organization, as a Pages::Read, a page at a time from next_cursor (spec, GET /v1/apps).
    def app_list(org_slug)
      Pages.read(max_pages: APP_PAGES) do |cursor|
        answer = machines_get("/apps", "org_slug" => org_slug, "limit" => APPS_PAGE, "cursor" => cursor)
        [ Array(answer["apps"]), answer["next_cursor"].presence ]
      end
    end

    def app(app_name) = machines_get("/apps/#{segment(app_name)}")

    def machines(app_name) = Array(machines_get("/apps/#{segment(app_name)}/machines"))

    # Every certificate of an app, as a Pages::Read, a page at a time from next_cursor (spec, GET /v1/apps/{app_name}/certificates).
    def certificates(app_name)
      Pages.read(max_pages: CERTIFICATE_PAGES) do |cursor|
        answer = machines_get("/apps/#{segment(app_name)}/certificates", "limit" => CERTIFICATES_PAGE, "cursor" => cursor)
        [ Array(answer["certificates"]), answer["next_cursor"].presence ]
      end
    end

    # The names of an app's secrets. show_secrets is never sent, so Fly answers names and digests and no value (spec,
    # GET /v1/apps/{app_name}/secrets, Secrets_list, and superfly/flyctl internal/appsecrets/secrets.go, which lists them
    # the same way).
    def secret_names(app_name) = Array(machines_get("/apps/#{segment(app_name)}/secrets")["secrets"]).filter_map { |secret| secret["name"].presence }

    def postgres_clusters(org_slug) = Array(machines_get("/postgres", "org_slug" => org_slug)["data"])

    def postgres_cluster(cluster_id) = machines_get("/postgres/#{segment(cluster_id)}")

    # A Managed Postgres cluster's databases by name (spec, Postgres_databases_list).
    def postgres_databases(cluster_id) = Array(machines_get("/postgres/#{segment(cluster_id)}/databases")["data"])

    # The top 20 queries by total execution time, read from Postgres's cumulative counters within the last range seconds,
    # at most a week (spec, Postgres_queries_slow).
    def postgres_slow_queries(cluster_id, range:) = Array(machines_get("/postgres/#{segment(cluster_id)}/queries/slow", "range" => range)["data"])

    # The queries running now in one database, which Fly takes by name (spec, Postgres_queries_active).
    def postgres_active_queries(cluster_id, database:) = Array(machines_get("/postgres/#{segment(cluster_id)}/queries/active", "database" => database)["data"])

    def restart_machine(app_name, machine_id) = machines_post("/apps/#{segment(app_name)}/machines/#{segment(machine_id)}/restart")

    # Machines_start, Machines_stop, Machines_suspend, Machines_cordon and Machines_uncordon in the spec. A stop sends no
    # body, so the machine gets its own stop signal. A cordon takes a running machine out of the Fly Proxy's routing,
    # and an uncordon puts it back.
    def start_machine(app_name, machine_id) = machines_post("/apps/#{segment(app_name)}/machines/#{segment(machine_id)}/start")

    def stop_machine(app_name, machine_id) = machines_post("/apps/#{segment(app_name)}/machines/#{segment(machine_id)}/stop")

    def suspend_machine(app_name, machine_id) = machines_post("/apps/#{segment(app_name)}/machines/#{segment(machine_id)}/suspend")

    def cordon_machine(app_name, machine_id) = machines_post("/apps/#{segment(app_name)}/machines/#{segment(machine_id)}/cordon")

    def uncordon_machine(app_name, machine_id) = machines_post("/apps/#{segment(app_name)}/machines/#{segment(machine_id)}/uncordon")

    # The whole config goes back with the change, and current_version makes Fly refuse it if the machine moved on.
    # skip_launch leaves a machine that was not running as it was (spec, UpdateMachineRequest).
    def update_machine(app_name, machine_id, config:, current_version:, skip_launch: false)
      body = { "config" => config, "current_version" => current_version, "skip_launch" => (true if skip_launch) }.compact
      machines_post("/apps/#{segment(app_name)}/machines/#{segment(machine_id)}", body)
    end

    # A new machine from a config, in a region, started (spec, Machines_create, CreateMachineRequest), as fly scale count
    # launches one from a machine of the same process group (superfly/flyctl, internal/command/scale/count_machines.go).
    def create_machine(app_name, config:, region:)
      machines_post("/apps/#{segment(app_name)}/machines", "config" => config, "region" => region)
    end

    # Destroys a machine, killing it first when it runs, as fly scale count does with Kill (spec, Machines_delete, force).
    def destroy_machine(app_name, machine_id)
      uri = URI.parse("#{MACHINES_ROOT}/apps/#{segment(app_name)}/machines/#{segment(machine_id)}")
      uri.query = URI.encode_www_form("force" => true)
      send_request(uri, Net::HTTP::Delete.new(uri))
    end

    # Waits until the machine is started, or at most timeout seconds, and answers whether it got there. version is the
    # machine version an update answered, so an old start does not count (spec, GET .../machines/{machine_id}/wait).
    def wait_started(app_name, machine_id, version: nil, timeout: WAIT_SECONDS) = wait_for(app_name, machine_id, STARTED, version: version, timeout: timeout)

    # The same wait for any state the spec's wait takes, such as stopped or suspended.
    def wait_for(app_name, machine_id, state, version: nil, timeout: WAIT_SECONDS)
      uri = URI.parse("#{MACHINES_ROOT}/apps/#{segment(app_name)}/machines/#{segment(machine_id)}/wait")
      answer = get(uri, { "state" => state, "version" => version, "timeout" => timeout }, read_timeout: timeout + WAIT_MARGIN)
      answer["ok"] != false && answer["state"].to_s.in?([ "", state ])
    end

    def releases(app_name, limit:)
      data = graphql(RELEASES_QUERY, "appName" => app_name, "limit" => limit)
      Array(data.dig("app", "releases", "nodes"))
    end

    # The release whose id or version is wanted, read page by page from the newest, or nil when none of the newest
    # RELEASE_PAGE * RELEASE_PAGES is it.
    def release(app_name, wanted)
      after = nil
      RELEASE_PAGES.times do
        page = graphql(RELEASE_PAGE_QUERY, "appName" => app_name, "limit" => RELEASE_PAGE, "after" => after).dig("app", "releases").to_h
        found = Array(page["nodes"]).find { |release| [ release["id"].to_s, release["version"].to_s ].include?(wanted.to_s) }
        return found if found

        after = page.dig("pageInfo", "endCursor")
        return nil unless page.dig("pageInfo", "hasNextPage") && after
      end
      nil
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

    # Any GET of the Machines API, by its path under MACHINES_HOST as the spec writes it (/v1/...), for the general read
    # (Integrations::ApiReads), which checks the path before it gets here.
    def read(path, query) = get(URI.parse("#{MACHINES_HOST}#{path}"), query)

    # One GraphQL query, for the general GraphQL read, whose guard (ReadGuards::Fly) shows it is a query before it gets here.
    def read_graphql(text, variables) = graphql(text, variables)

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
      errors = Array(answer["errors"]).filter_map { |error| Sentence.clean(error["message"]) }
      raise Error, "Fly answered: #{errors.join(', ')}." if errors.any? && answer["data"].blank?

      answer["data"] || {}
    end

    def get(uri, query, read_timeout: READ_TIMEOUT)
      uri.query = URI.encode_www_form(query.compact) if query.compact.any?
      send_request(uri, Net::HTTP::Get.new(uri), read_timeout: read_timeout)
    end

    def send_request(uri, request, read_timeout: READ_TIMEOUT)
      request["Authorization"] = authorization
      request["Accept"] = "application/json"
      Http.json(uri, request, error_class: Error, provider_name: PROVIDER, read_timeout: read_timeout,
                              refine: ->(code, _reason) { REFINED[code] })
    end

    def segment(value) = Http.segment(value)
  end
end
