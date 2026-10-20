require "test_helper"

module Integrations
  class DigitaloceanApiTest < ActiveSupport::TestCase
    setup do
      @api = DigitaloceanApi.new("dop-token")
    end

    test "a list follows DigitalOcean's next page link, with the token, until there is none, and says when it stopped short" do
      Http.expects(:request).twice.with do |uri, request, **|
        uri.path == "/v2/apps" && request["Authorization"] == "Bearer dop-token" && URI.decode_www_form(uri.query).include?([ "per_page", "200" ])
      end.returns(response(200, { apps: [ { id: "a" } ], links: { pages: { next: "https://api.digitalocean.com/v2/apps?page=2" } } }),
                  response(200, { apps: [ { id: "b" } ], links: {} }))

      listed = @api.apps
      assert_equal %w[a b], listed.items.map { |app| app["id"] }
      assert_not listed.incomplete?

      Http.stubs(:request).returns(response(200, { droplets: [ { id: 1 } ], links: { pages: { next: "https://api.digitalocean.com/v2/droplets?page=2" } } }))
      assert @api.droplets.incomplete?
    end

    test "logs are read from the archived files and the live address DigitalOcean links to, without sending the token there" do
      Http.expects(:request).with do |uri, request, **|
        uri.path == "/v2/apps/app-1/components/web/logs" && URI.decode_www_form(uri.query).sort == [ %w[follow false], %w[type RUN] ] &&
          request["Authorization"] == "Bearer dop-token"
      end.returns(response(200, { historic_urls: [ "https://logs.example/run.log" ], live_url: "wss://logs.example/live" }))
      Http.expects(:download).with("https://logs.example/run.log", provider_key: DigitaloceanApi::PROVIDER_KEY, error_class: DigitaloceanApi::Error,
                                   limit: DigitaloceanApi::LOG_BYTES).returns("web 2026-10-01T10:00:00Z started\n")

      where = @api.logs("app-1", type: "RUN", component: "web")

      assert_equal({ historic: [ "https://logs.example/run.log" ], live: "wss://logs.example/live" }, where)
      assert_equal "web 2026-10-01T10:00:00Z started\n", @api.log_file(where[:historic].first)
    end

    test "one deployment's logs, of one component or every one, and the deployment itself, are read under that deployment" do
      Http.expects(:request).with do |uri, **|
        uri.path == "/v2/apps/app-1/deployments/dep-9/components/web/logs" && URI.decode_www_form(uri.query).include?(%w[type BUILD])
      end.returns(response(200, { historic_urls: [ "https://logs.example/web.log" ] }))
      assert_equal [ "https://logs.example/web.log" ], @api.logs("app-1", type: "BUILD", component: "web", deployment: "dep-9")[:historic]

      Http.expects(:request).with { |uri, **| uri.path == "/v2/apps/app-1/deployments/dep-9/logs" }.returns(response(200, { historic_urls: [] }))
      assert_equal({ historic: [], live: nil }, @api.logs("app-1", type: "DEPLOY", deployment: "dep-9"))

      Http.expects(:request).with { |uri, **| uri.path == "/v2/apps/app-1/deployments/dep-9" }.returns(response(200, { deployment: { id: "dep-9", phase: "ERROR" } }))
      assert_equal "ERROR", @api.deployment("app-1", "dep-9")["phase"]

      Http.stubs(:request).returns(response(404, { id: "not_found", message: "deployment not found" }))
      assert_raises(DigitaloceanApi::NotFound) { @api.deployment("app-1", "dep-0") }
    end

    test "a change is sent as JSON, and DigitalOcean's refusal is raised with its own reason" do
      Http.expects(:request).with do |uri, request, **|
        uri.path == "/v2/apps/app-1/rollback" && request.is_a?(Net::HTTP::Post) && JSON.parse(request.body) == { "deployment_id" => "dep-1" }
      end.returns(response(403, { id: "forbidden", message: "You do not have access for the attempted action." }))

      error = assert_raises(DigitaloceanApi::Error) { @api.rollback("app-1", "dep-1") }

      assert_equal "DigitalOcean answered 403: You do not have access for the attempted action.", error.message
    end

    test "a live log is read from its address as each message's data, and a job run's logs under its job" do
      Http::LiveSocket.expects(:messages).with("wss://logs.example/live?token=t", provider_key: DigitaloceanApi::PROVIDER_KEY, error_class: DigitaloceanApi::Error,
                                               limit: DigitaloceanApi::LOG_BYTES, seconds: DigitaloceanApi::LIVE_SECONDS)
                      .returns([ { data: "web 2026-10-01T10:00:00Z one\n" }.to_json, "not json\n" ])
      assert_equal "web 2026-10-01T10:00:00Z one\nnot json\n", @api.live_log("wss://logs.example/live?token=t")

      Http.expects(:request).with do |uri, **|
        uri.path == "/v2/apps/app-1/jobs/migrate/invocations/inv-1/logs" && URI.decode_www_form(uri.query).sort == [ %w[follow false], %w[type JOB_INVOCATION] ]
      end.returns(response(200, { live_url: "wss://logs.example/job" }))
      assert_equal({ historic: [], live: "wss://logs.example/job" }, @api.job_invocation_logs("app-1", "migrate", "inv-1"))
    end

    test "rollbacks are checked, kept and undone, deployments made and cancelled, and job runs read and cancelled at their documented paths" do
      sent = []
      Http.stubs(:request).with do |uri, request, **|
        sent << [ request.method, uri.path, uri.query, request.body ]
        true
      end.returns(response(200, { valid: true, deployment: { id: "dep-5" }, job_invocations: [ { id: "inv-1" } ], events: [], alerts: [], actions: [] }))

      @api.validate_rollback("app-1", "dep-1")
      @api.commit_rollback("app-1")
      @api.revert_rollback("app-1")
      @api.create_deployment("app-1", force_build: true)
      @api.cancel_deployment("app-1", "dep-3")
      assert_equal [ { "id" => "inv-1" } ], @api.job_invocations("app-1", limit: 5, job_name: "migrate")
      @api.cancel_job_invocation("app-1", "inv-1", job_name: "migrate")
      @api.events("app-1", limit: 20, type: "AUTOSCALING")
      @api.alerts("app-1")
      @api.event("app-1", "ev-2")
      @api.cancel_event("app-1", "ev-2")

      assert_equal [
        [ "POST", "/v2/apps/app-1/rollback/validate", nil, { "deployment_id" => "dep-1" }.to_json ],
        [ "POST", "/v2/apps/app-1/rollback/commit", nil, nil ],
        [ "POST", "/v2/apps/app-1/rollback/revert", nil, nil ],
        [ "POST", "/v2/apps/app-1/deployments", nil, { "force_build" => true }.to_json ],
        [ "POST", "/v2/apps/app-1/deployments/dep-3/cancel", nil, nil ],
        [ "GET", "/v2/apps/app-1/job-invocations", "per_page=5&job_names=migrate", nil ],
        [ "POST", "/v2/apps/app-1/job-invocations/inv-1/cancel", "job_name=migrate", nil ],
        [ "GET", "/v2/apps/app-1/events", "per_page=20&event_types=AUTOSCALING", nil ],
        [ "GET", "/v2/apps/app-1/alerts", nil, nil ],
        [ "GET", "/v2/apps/app-1/events/ev-2", nil, nil ],
        [ "POST", "/v2/apps/app-1/events/ev-2/cancel", nil, nil ]
      ], sent
    end

    test "a Droplet's actions are the newest of its first page and its last" do
      Http.expects(:request).with { |uri, **| uri.path == "/v2/droplets/7/actions" && uri.query.include?("page=1") }
          .returns(response(200, { actions: [ { id: 1, started_at: "2026-01-01T00:00:00Z" } ],
                                   links: { pages: { last: "https://api.digitalocean.com/v2/droplets/7/actions?page=3&per_page=200" } } }))
      Http.expects(:request).with { |uri, **| uri.path == "/v2/droplets/7/actions" && uri.query.include?("page=3") }
          .returns(response(200, { actions: [ { id: 9, started_at: "2026-10-01T00:00:00Z" } ] }))

      assert_equal [ 9 ], @api.droplet_actions(7, limit: 1).map { |action| action["id"] }
    end

    test "being asked to slow down is its own error, so a sweep stops" do
      Http.stubs(:request).returns(response(429, { id: "too_many_requests", message: "API Rate limit exceeded." }))

      error = assert_raises(DigitaloceanApi::Error) { @api.droplets }
      assert_kind_of Integrations::RateLimited, error
    end

    test "metrics come back as DigitalOcean's series" do
      Http.expects(:request).with do |uri, **|
        uri.path == "/v2/monitoring/metrics/apps/cpu_percentage" && URI.decode_www_form(uri.query).include?(%w[app_id app-1])
      end.returns(response(200, { status: "success", data: { resultType: "matrix", result: [ { metric: { app_component: "web" }, values: [ [ 1, "5" ] ] } ] } }))

      assert_equal [ { "metric" => { "app_component" => "web" }, "values" => [ [ 1, "5" ] ] } ],
                   @api.metrics("apps/cpu_percentage", "app_id" => "app-1", "start" => 1, "end" => 2)
    end

    private

    def response(code, body)
      stub(code: code.to_s, body: body.to_json)
    end
  end
end
