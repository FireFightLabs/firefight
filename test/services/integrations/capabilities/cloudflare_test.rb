require "test_helper"

class Integrations::Capabilities::CloudflareTest < ActiveSupport::TestCase
  ACCOUNT = "acc123".freeze

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @integration = @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: "cloudflare", name: "Cloudflare", slug: "cloudflare",
                                                   settings: { "server_url" => "https://mcp.cloudflare.com/mcp" })
    @row = @integration.integration_environments.create!
    @integration.tools.create!(name: "execute", description: "Runs a script", read_only: false, enabled: true, params_schema: { "type" => "object" })
    @worker = resource!(ResourceMap::KIND_WORKER, "api-worker", "api-worker", "workers-and-pages")
    @zone = resource!(ResourceMap::KIND_ZONE, "zone-1", "example.com", "example.com")
    @site = resource!(ResourceMap::KIND_SITE, "docs", "docs", "workers-and-pages")
  end

  test "a Worker's logs are one Workers Observability query Firefight writes, and its events read back as log lines" do
    call = resolve(Integrations::Capabilities::LOGS, "resource" => "api-worker", "text" => "timeout", "minutes" => 15)

    options = request_of(call)
    assert_equal [ "POST", "/accounts/#{ACCOUNT}/workers/observability/telemetry/query" ], options.values_at("method", "path")
    assert_equal [ "events", 200, true ], options["body"].values_at("view", "limit", "dry")
    assert_includes call.arguments["code"], "const to = Date.now(); const from = Math.max(to - 15 * 60000"
    assert_includes call.arguments["code"], "request.body.timeframe = { from, to };"
    assert_includes options.dig("body", "parameters", "filters"), { "key" => "$metadata.service", "operation" => "eq", "type" => "string", "value" => "api-worker" }
    assert_equal ACCOUNT, call.arguments["account_id"]

    answer = call.present_result(text_result({ "result" => { "events" => { "events" => [
      { "$metadata" => { "timestamp" => 1_759_400_000_000, "message" => "upstream timeout" } }
    ] } } }))
    assert_match "upstream timeout", answer.dig("content", 0, "text")
    assert_match "https://dash.cloudflare.com/#{ACCOUNT}/workers-and-pages", answer.dig("content", 0, "text")
    assert_match "stream must be app or build",
                 assert_raises(Integrations::Capabilities::Unroutable) { resolve(Integrations::Capabilities::LOGS, "resource" => "api-worker", "stream" => "requests") }.message
  end

  test "a Worker's metrics are bucketed into a chart, and a zone's come from its hourly request counts" do
    call = resolve(Integrations::Capabilities::METRICS, "resource" => "api-worker", "metrics" => %w[requests errors], "minutes" => 60)
    assert_equal "/graphql", request_of(call)["path"]
    rows = [ 0, 30, 70 ].map do |seconds|
      { "sum" => { "requests" => 10, "errors" => 1 }, "quantiles" => { "cpuTimeP50" => 2000 }, "dimensions" => { "datetime" => (Time.utc(2026, 10, 3, 10) + seconds).iso8601 } }
    end
    answer = call.present_result(text_result({ "data" => { "viewer" => { "accounts" => [ { "workersInvocationsAdaptive" => rows } ] } } }))
    charts = answer.dig(Integrations::Telemetry::STRUCTURED, Integrations::Telemetry::CHARTS)
    assert_equal [ "Requests of api-worker", "Errors of api-worker" ], charts.map { |chart| chart["title"] }
    assert_equal [ 20.0, 10.0 ], charts.first.dig("series", 0, "points").map(&:last)

    zone = resolve(Integrations::Capabilities::METRICS, "resource" => "example.com", "metrics" => [ "http_5xx" ])
    assert_includes request_of(zone).dig("body", "query"), "edgeResponseStatus_geq: 500"
    answer = zone.present_result(text_result({ "data" => { "viewer" => { "zones" => [ { "server" => [ { "count" => 4, "dimensions" => { "datetimeHour" => "2026-10-03T10:00:00Z" } } ] } ] } } }))
    assert_match "Counted every hour", answer.dig("content", 0, "text")
    assert_match "Cloudflare does not keep cpu",
                 assert_raises(Integrations::Capabilities::Unroutable) { resolve(Integrations::Capabilities::METRICS, "resource" => "example.com", "metrics" => [ "cpu" ]) }.message
  end

  test "deploys list with the id rollback takes, and a rollback is the request Cloudflare's docs give" do
    deploys = resolve(Integrations::Capabilities::DEPLOYS, "resource" => "api-worker")
    assert_includes deploys.arguments["code"], %({"method":"GET","path":"/accounts/#{ACCOUNT}/workers/scripts/api-worker/deployments"})
    assert_includes deploys.arguments["code"], %({"method":"GET","path":"/accounts/#{ACCOUNT}/workers/scripts/api-worker/versions","query":{"per_page":10}})
    answer = deploys.present_result(text_result({ "result" => { "deployments" => [
      { "id" => "dep-1", "created_on" => "2026-10-03T09:00:00Z", "source" => "wrangler", "author_email" => "a@example.com",
        "versions" => [ { "version_id" => "ver-9", "percentage" => 100 } ] }
    ] }, "versions" => { "items" => [
      { "id" => "ver-10", "number" => 10, "metadata" => { "created_on" => "2026-10-03T10:00:00Z", "author_email" => "b@example.com", "source" => "wrangler" } },
      { "id" => "ver-9", "number" => 9, "metadata" => { "created_on" => "2026-10-03T08:55:00Z" } }
    ] } }))
    text = answer.dig("content", 0, "text")
    assert_match "version ver-9 at 100%", text
    assert_match "rollback takes a version id", text
    assert_match "2026-10-03T10:00:00Z, version ver-10, number 10, by b@example.com, from wrangler, in no deployment listed", text
    assert_match "2026-10-03T08:55:00Z, version ver-9, number 9, deployed", text
    assert_equal [ "dep-1" ], Integrations::Capabilities::Deploys.deploys_of(answer).map(&:id), "a version alone is not a deploy"

    version = "5f9e1a2b-0c3d-4e5f-8a9b-0c1d2e3f4a5b"
    worker = resolve(Integrations::Capabilities::ROLLBACK, "resource" => "api-worker", "to" => version)
    assert_equal [ { "version_id" => version, "percentage" => 100 } ], request_of(worker).dig("body", "versions")
    deployment = "f64788e9-fccd-4d4a-a28a-cb84f88f6a1c"
    site = resolve(Integrations::Capabilities::ROLLBACK, "resource" => "docs", "to" => deployment)
    assert_equal "/accounts/#{ACCOUNT}/pages/projects/docs/deployments/#{deployment}/rollback", request_of(site)["path"]
  end

  test "a rollback target that is not an id is refused, so it can never reach another endpoint" do
    escape = "x/../../../../../zones/z-1/purge_cache?"
    [ "api-worker", "docs" ].each do |resource|
      refusal = assert_raises(Integrations::Capabilities::Unroutable) { resolve(Integrations::Capabilities::ROLLBACK, "resource" => resource, "to" => escape) }
      assert_match "recent_deploys", refusal.message
    end
  end

  test "the same request reads the same each time, so a replay matches it, and a failed answer is thrown as an error" do
    first = resolve(Integrations::Capabilities::METRICS, "resource" => "api-worker", "minutes" => 30)
    travel 5.minutes
    again = resolve(Integrations::Capabilities::METRICS, "resource" => "api-worker", "minutes" => 30)

    assert_equal first.arguments, again.arguments
    assert_includes first.arguments["code"], "answer.success === false"
    assert_includes first.arguments["code"], "request.body.variables.start = new Date(from).toISOString();"
  end

  test "an error or an answer that is not JSON reaches the agent in Cloudflare's own words" do
    call = resolve(Integrations::Capabilities::STATUS, "resource" => "example.com")
    error = { "content" => [ { "type" => "text", "text" => "Authentication error" } ], "isError" => true }

    assert_equal error, call.present_result(error)
    assert_equal "not json", call.present_result(text_result("not json")).dig("content", 0, "text")
  end

  test "a Worker's deployments are its deploys, the first one serving, and a Pages project's carry their commit and stage, a preview never serving" do
    worker = resolve(Integrations::Capabilities::DEPLOYS, "resource" => "api-worker").present_result(text_result({ "result" => { "deployments" => [
      { "id" => "dep-2", "created_on" => "2026-10-03T10:00:00Z", "versions" => [ { "version_id" => "ver-9", "percentage" => 10 }, { "version_id" => "ver-10", "percentage" => 90 } ] },
      { "id" => "dep-1", "created_on" => "2026-10-03T09:00:00Z", "versions" => [ { "version_id" => "ver-9", "percentage" => 100 } ] }
    ] } }))
    assert_equal [ [ "dep-2", "ver-10,ver-9", "succeeded", true, Time.utc(2026, 10, 3, 10) ], [ "dep-1", "ver-9", "succeeded", false, Time.utc(2026, 10, 3, 9) ] ],
                 Integrations::Capabilities::Deploys.deploys_of(worker).map { |deploy| [ deploy.id, deploy.version, deploy.status, deploy.live, deploy.finished_at ] }
    assert_match "Latest 2 deployments of api-worker, newest first. rollback takes a version id.\n2026-10-03T10:00:00Z, deployment dep-2, version ver-9 at 10% and version ver-10 at 90%",
                 worker.dig("content", 0, "text")

    pages = resolve(Integrations::Capabilities::DEPLOYS, "resource" => "docs").present_result(text_result({ "result" => [
      { "id" => "d3", "environment" => "production", "created_on" => "2026-10-01T10:00:00Z",
        "latest_stage" => { "name" => "build", "status" => "active" } },
      { "id" => "d2", "environment" => "production", "created_on" => "2026-10-01T09:00:00Z",
        "latest_stage" => { "name" => "deploy", "status" => "success", "ended_on" => "2026-10-01T09:03:10Z" },
        "deployment_trigger" => { "metadata" => { "commit_hash" => "C4E4267D46E638AC", "branch" => "main", "commit_message" => "Fix nav" } } },
      { "id" => "d1", "environment" => "preview", "created_on" => "2026-10-01T08:00:00Z",
        "latest_stage" => { "name" => "build", "status" => "failure", "ended_on" => "2026-10-01T08:02:00Z" } }
    ] }))
    assert_equal [ [ "d3", nil, "running", nil, nil ], [ "d2", "c4e4267d46e638ac", "succeeded", nil, Time.utc(2026, 10, 1, 9, 3, 10) ],
                   [ "d1", nil, "failed", false, Time.utc(2026, 10, 1, 8, 2) ] ],
                 Integrations::Capabilities::Deploys.deploys_of(pages).map { |deploy| [ deploy.id, deploy.commit, deploy.status, deploy.live, deploy.finished_at ] }
    assert_equal "main", Integrations::Capabilities::Deploys.deploys_of(pages).second.branch
    assert_equal [], Integrations::Capabilities::Deploys.deploys_of(resolve(Integrations::Capabilities::DEPLOYS, "resource" => "docs").present_result(text_result({ "result" => [] })))
  end

  test "run history is a Pages project's deployments read stage by stage" do
    call = resolve(Integrations::Capabilities::HISTORY, "resource" => "docs", "name" => "production")
    assert_equal [ "GET", "/accounts/#{ACCOUNT}/pages/projects/docs/deployments" ], request_of(call).values_at("method", "path")

    answer = call.present_result(text_result({ "result" => [
      { "id" => "d2", "environment" => "production", "created_on" => "2026-10-01T09:00:00Z", "url" => "https://d2.docs.pages.dev",
        "latest_stage" => { "name" => "deploy", "status" => "success", "ended_on" => "2026-10-01T09:03:10Z" },
        "stages" => [ { "name" => "queued", "started_on" => "2026-10-01T09:00:10Z" }, { "name" => "deploy", "started_on" => "2026-10-01T09:03:00Z" } ],
        "deployment_trigger" => { "metadata" => { "commit_hash" => "c4e4267d46e638ac", "commit_message" => "Fix nav" } } },
      { "id" => "d3", "environment" => "production", "created_on" => "2026-10-01T10:00:00Z",
        "latest_stage" => { "name" => "build", "status" => "success", "ended_on" => "2026-10-01T10:01:00Z" } },
      { "id" => "d1", "environment" => "preview", "created_on" => "2026-10-01T08:00:00Z",
        "latest_stage" => { "name" => "build", "status" => "failure", "ended_on" => "2026-10-01T08:02:00Z" } }
    ] }))
    runs = Integrations::Capabilities::History.runs_of(answer)
    assert_equal [ [ "d3", "running", nil ], [ "d2", "succeeded", 180 ] ], runs.map { |run| [ run.id, run.status, run.seconds ] }
    assert_equal "c4e4267d46e6 Fix nav", runs.second.detail
    assert_equal "https://dash.cloudflare.com/#{ACCOUNT}/pages/view/docs/d2", runs.second.url
  end

  test "a Worker's run history is its Workers Builds, by the tag the map keeps or one looked up, each build's outcome its status" do
    @worker.update!(details: { "tag" => "1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d" })
    call = resolve(Integrations::Capabilities::HISTORY, "resource" => "api-worker")
    assert_includes call.arguments["code"], %(const tag = "1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d";)
    assert_includes call.arguments["code"], %("/accounts/#{ACCOUNT}/builds/workers/" + tag + "/builds")

    answer = call.present_result(text_result({ "result" => [
      { "build_uuid" => "b-2", "status" => "running", "created_on" => "2026-10-03T10:00:00Z", "build_trigger_metadata" => { "branch" => "main" } },
      { "build_uuid" => "b-1", "status" => "stopped", "build_outcome" => "fail", "created_on" => "2026-10-03T09:00:00Z", "stopped_on" => "2026-10-03T09:02:00Z",
        "build_trigger_metadata" => { "branch" => "main", "commit_hash" => "abcdef1234567890", "commit_message" => "Break it\nmore" } },
      { "build_uuid" => "b-0", "status" => "stopped", "build_outcome" => "skipped", "created_on" => "2026-10-03T08:00:00Z", "stopped_on" => "2026-10-03T08:00:01Z" }
    ] }))
    runs = Integrations::Capabilities::History.runs_of(answer)
    assert_equal [ [ "b-2", "running", nil ], [ "b-1", "failed", 120 ], [ "b-0", "cancelled", 1 ] ], runs.map { |run| [ run.id, run.status, run.seconds ] }
    assert_equal [ "main build", "abcdef123456 Break it", "https://dash.cloudflare.com/#{ACCOUNT}/workers/services/view/api-worker/production/deployments" ],
                 runs.second.to_h.values_at("name", "detail", "url")

    @worker.update!(details: {})
    looked_up = resolve(Integrations::Capabilities::HISTORY, "resource" => "api-worker")
    assert_includes looked_up.arguments["code"], %("path":"/accounts/#{ACCOUNT}/workers/scripts")
    assert_includes looked_up.arguments["code"], %(each.id === "api-worker")
  end

  test "one Workers build is read by its id, and one of another Worker is not taken for this one's" do
    call = resolve(Integrations::Capabilities::HISTORY, "resource" => "api-worker", "run" => "f64788e9-fccd-4d4a-a28a-cb84f88f6a1c")
    assert_includes call.arguments["code"], %("path":"/accounts/#{ACCOUNT}/builds/builds/f64788e9-fccd-4d4a-a28a-cb84f88f6a1c")
    build = { "build_uuid" => "f64788e9", "status" => "queued", "created_on" => "2026-10-03T10:00:00Z", "trigger" => { "external_script_id" => "tag-1" } }

    assert_equal "queued", Integrations::Capabilities::History.runs_of(call.present_result(text_result({ "result" => build, "tag" => "tag-1" }))).sole.status
    assert_match "Cloudflare has no build", call.present_result(text_result({ "result" => build, "tag" => "tag-2" })).dig("content", 0, "text")
    assert_raises(Integrations::Capabilities::Unroutable) { resolve(Integrations::Capabilities::HISTORY, "resource" => "api-worker", "run" => "../zones") }
  end

  test "a Worker's build log is read page by page, of the build named or its newest, with a link to its build history" do
    named = resolve(Integrations::Capabilities::LOGS, "resource" => "api-worker", "stream" => "build", "deployment" => "f64788e9-fccd-4d4a-a28a-cb84f88f6a1c")
    assert_includes named.arguments["code"], %(const build = "f64788e9-fccd-4d4a-a28a-cb84f88f6a1c";)
    assert_includes named.arguments["code"], %("/accounts/#{ACCOUNT}/builds/builds/" + build + "/logs")
    answer = named.present_result(text_result({ "build" => "f64788e9", "result" => { "lines" => [ [ 1_759_482_000_000, "npm ERR! missing script" ], [ 1_759_481_990_000, "Cloning" ] ],
                                                                     "truncated" => false, "more" => true } }))
    text = answer.dig("content", 0, "text")
    assert_match "build f64788e9 of api-worker", text
    assert_match "npm ERR! missing script", text
    assert_match "Cloudflare holds more of this log than was read.", text
    assert_match "/workers/services/view/api-worker/production/deployments", text

    newest = resolve(Integrations::Capabilities::LOGS, "resource" => "api-worker", "stream" => "build", "text" => "ERR")
    assert_includes newest.arguments["code"], "query: { per_page: 1 }"
    assert_match "has no Workers builds", newest.present_result(text_result({ "result" => nil })).dig("content", 0, "text")
    assert_raises(Integrations::Capabilities::Unroutable) { resolve(Integrations::Capabilities::LOGS, "resource" => "api-worker", "stream" => "build", "deployment" => "x/../y") }
  end

  test "one Pages deployment is read by its id, its stages are its parts, and each reads that deployment's build log as a read" do
    call = resolve(Integrations::Capabilities::HISTORY, "resource" => "docs", "run" => "d2a1-4b")
    assert_equal [ "GET", "/accounts/#{ACCOUNT}/pages/projects/docs/deployments/d2a1-4b" ], request_of(call).values_at("method", "path")
    assert_raises(Integrations::Capabilities::Unroutable) { resolve(Integrations::Capabilities::HISTORY, "resource" => "docs", "run" => "../zones") }

    # The shape of Cloudflare's Pages API, deployments, get deployment info.
    answer = call.present_result(text_result({ "success" => true, "result" => {
      "id" => "d2a1-4b", "environment" => "production", "created_on" => "2026-10-01T09:00:00Z", "url" => "https://d2a1.docs.pages.dev",
      "latest_stage" => { "name" => "build", "status" => "failure", "started_on" => "2026-10-01T09:01:00Z", "ended_on" => "2026-10-01T09:02:30Z" },
      "stages" => [
        { "name" => "queued", "status" => "success", "started_on" => "2026-10-01T09:00:00Z", "ended_on" => "2026-10-01T09:00:05Z" },
        { "name" => "initialize", "status" => "success", "started_on" => "2026-10-01T09:00:05Z", "ended_on" => "2026-10-01T09:00:40Z" },
        { "name" => "clone_repo", "status" => "success", "started_on" => "2026-10-01T09:00:40Z", "ended_on" => "2026-10-01T09:01:00Z" },
        { "name" => "build", "status" => "failure", "started_on" => "2026-10-01T09:01:00Z", "ended_on" => "2026-10-01T09:02:30Z" },
        { "name" => "deploy", "status" => "idle", "started_on" => nil, "ended_on" => nil }
      ]
    } }))
    run = Integrations::Capabilities::History.runs_of(answer).sole
    assert_equal [ "d2a1-4b", "failed", "https://dash.cloudflare.com/#{ACCOUNT}/pages/view/docs/d2a1-4b" ], [ run.id, run.status, run.url ]
    assert_equal [ %w[queued succeeded], %w[initialize succeeded], %w[clone_repo succeeded], %w[build failed], %w[deploy queued] ],
                 run.parts.map { |part| [ part.name, part.status ] }
    failed = run.first_failed_part
    assert_equal [ "build", 90 ], [ failed.name, failed.seconds ]
    log = failed.log
    assert_equal "execute", log[Integrations::Capabilities::History::LOG_TOOL]
    arguments = log[Integrations::Capabilities::History::LOG_ARGUMENTS]
    assert_includes arguments["code"], "/accounts/#{ACCOUNT}/pages/projects/docs/deployments/d2a1-4b/history/logs"
    assert Integrations::ReadGuards::Cloudflare.reads?("execute", arguments)

    missing = call.present_result(text_result({ "success" => true, "result" => nil }))
    assert_match "Cloudflare has no deployment d2a1-4b of docs.", missing.dig("content", 0, "text")
  end

  test "a Pages project's build log is the named deployment's, or its newest one's, read as lines with their time" do
    named = resolve(Integrations::Capabilities::LOGS, "resource" => "docs", "deployment" => "d2a1-4b", "text" => "error")
    assert Integrations::ReadGuards::Cloudflare.reads?("execute", named.arguments)
    assert_includes named.arguments["code"], "/pages/projects/docs/deployments/d2a1-4b/history/logs"

    # The shape of Cloudflare's Pages API, deployments, get deployment logs.
    answer = named.present_result(text_result({ "success" => true, "result" => { "total" => 2, "includes_container_logs" => true, "data" => [
      { "line" => "Installing dependencies", "ts" => "2026-10-01T09:01:05Z" },
      { "line" => "error: Cannot find module 'astro'", "ts" => "2026-10-01T09:02:20Z" }
    ] } }))
    text = answer.dig("content", 0, "text")
    assert_match "Cannot find module 'astro'", text
    assert_no_match "Installing dependencies", text
    assert_match "https://dash.cloudflare.com/#{ACCOUNT}/pages/view/docs/d2a1-4b", text

    newest = resolve(Integrations::Capabilities::LOGS, "resource" => "docs")
    assert_includes newest.arguments["code"], %("path":"/accounts/#{ACCOUNT}/pages/projects/docs/deployments")
    answer = newest.present_result(text_result({ "success" => true, "deployment" => "e5f6", "result" => { "data" => [ { "line" => "Build failed", "ts" => "2026-10-01T09:02:20Z" } ] } }))
    assert_match "deployment e5f6 of docs", answer.dig("content", 0, "text")
    assert_match "has no deployments", newest.present_result(text_result({ "result" => nil })).dig("content", 0, "text")

    assert_raises(Integrations::Capabilities::Unroutable) { resolve(Integrations::Capabilities::LOGS, "resource" => "docs", "stream" => "app") }
    assert_raises(Integrations::Capabilities::Unroutable) { resolve(Integrations::Capabilities::LOGS, "resource" => "docs", "deployment" => "x/../y") }
  end

  private

  def resolve(key, given) = Integrations::Capabilities.resolve(@workspace, key, given, principal: map_reader)

  # The request inside the script Firefight wrote, read back out of its JSON literal.
  def request_of(call)
    JSON.parse(call.arguments["code"][/const request = (\{.*?\}); (?:const to|const answer)/, 1])
  end

  def text_result(data) = { "content" => [ { "type" => "text", "text" => data.is_a?(String) ? data : data.to_json } ] }

  def resource!(kind, id, name, page)
    ResourceMap::Resource.create!(workspace: @workspace, provider: "cloudflare", account: "Acme", kind: kind, external_id: id, name: name,
                                  url: "https://dash.cloudflare.com/#{ACCOUNT}/#{page}", integration_environment: @row,
                                  first_seen_at: Time.current, last_seen_at: Time.current)
  end
end
