require "test_helper"

module Integrations
  module Packs
    class TinybirdTest < ActiveSupport::TestCase
      WORKSPACE = { "id" => "w-1", "name" => "analytics" }.freeze
      EVENTS = { "id" => "t_events", "name" => "events", "engine" => { "engine" => "MergeTree", "engine_sorting_key" => "timestamp" },
                 "statistics" => { "row_count" => 1200, "bytes" => 4096 }, "used_by" => [ { "id" => "t_top", "name" => "top_pages" } ] }.freeze
      TOP_PAGES = { "id" => "t_top", "name" => "top_pages", "endpoint" => "t_node2", "description" => "Most visited pages",
                    "nodes" => [ { "id" => "t_node1", "name" => "filtered", "dependencies" => [ "events" ] },
                                 { "id" => "t_node2", "name" => "endpoint", "dependencies" => [ "filtered" ],
                                   "params" => [ { "name" => "date_from", "type" => "Date", "required" => true } ] } ] }.freeze
      COPY = { "id" => "t_copy", "name" => "daily_copy", "endpoint" => nil, "type" => "copy", "nodes" => [] }.freeze
      SITE = "https://cloud.tinybird.co/aws/us-west-2/analytics".freeze

      setup do
        @workspace = workspaces(:slack_workspace_one)
        @integration = Integration.create!(workspace: @workspace, kind: Integration::KIND_NATIVE, provider: Tinybird::PROVIDER_KEY, name: "Tinybird",
                                           settings: { Integration::REGION_SETTING => "aws-us-west-2" })
        @row = @integration.integration_environments.create!
        Tinybird.store_credentials!(@row, Tinybird::TOKEN => " p.eyJ1IjoidyJ9.sig ")
        @pack = Tinybird.new(@integration)
        TinybirdApi.any_instance.stubs(:workspace).returns(WORKSPACE)
        TinybirdApi.any_instance.stubs(:datasources).returns([ EVENTS ])
        TinybirdApi.any_instance.stubs(:pipes).returns([ TOP_PAGES, COPY ])
        travel_to Time.zone.parse("2026-10-04T12:00:00Z")
      end

      test "the token is stored trimmed, every tool only reads, and the form checks the token in the region chosen" do
        assert_equal "p.eyJ1IjoidyJ9.sig", @row.reload.credentials_hash[Tinybird::TOKEN]
        assert_equal [ Tinybird::TOKEN ], Tinybird.credential_fields.map(&:key)
        assert Tinybird.tool_definitions.all?(&:read_only)
        assert_equal "Paste a token.", Tinybird.credential_refusal({ Tinybird::TOKEN => " " })

        region = IntegrationProvider.find(Tinybird::PROVIDER_KEY).region("gcp-europe-west2")
        TinybirdApi.expects(:new).with("p.x", region: "gcp-europe-west2").returns(api = mock)
        api.expects(:workspace).returns(WORKSPACE)
        api.expects(:query).with(Tinybird::HEALTH_QUERY).returns("data" => [])
        assert_nil Tinybird.credential_refusal({ Tinybird::TOKEN => "p.x" }, region: region)

        TinybirdApi.unstub(:new)
        TinybirdApi.any_instance.stubs(:workspace).raises(TinybirdApi::Refused, "Tinybird answered 403: invalid authentication token")
        assert_equal "Tinybird refused this token in London, GCP (api.europe-west2.gcp.tinybird.co): Tinybird answered 403: invalid " \
                     "authentication token. Check the region the workspace is in, and that the token has the WORKSPACE:READ_ALL scope.",
                     Tinybird.credential_refusal({ Tinybird::TOKEN => "p.x" }, region: region)
      end

      test "the map holds the workspace, its data sources and its endpoints, linked, with how each stood in the last hour" do
        stub_queries(
          "pipe_stats_rt" => [ { "pipe_id" => "t_top", "name" => "top_pages", "requests" => "40", "failed" => "3", "server_errors" => "2", "p95" => 0.2 } ],
          "datasources_ops_log" => [ { "datasource_id" => "t_events", "name" => "events", "ok" => "10", "failed" => "0", "last_error" => "" } ],
          "jobs_log" => [ { "created_at" => "2026-10-04 11:50:00", "job_id" => "j1", "status" => "working", "message" => "" } ]
        )

        snapshot = @pack.map_of(@row)
        workspace, events, endpoint = snapshot.resources

        assert_equal [ Tinybird::PROVIDER_KEY, "w-1", ResourceMap::KIND_DATABASE, "w-1" ], workspace.key
        assert_equal [ "analytics", "deploying", SITE ], [ workspace.name, workspace.status, workspace.url ]
        assert_equal({ "type" => "Workspace", "region" => "Oregon, AWS (api.us-west-2.aws.tinybird.co)" }, workspace.details)
        assert_equal [ "events", "healthy", { "type" => "Data source", "engine" => "MergeTree" } ], [ events.name, events.status, events.details ]
        assert_equal [ ResourceMap::KIND_FUNCTION, "top_pages", "degraded" ], [ endpoint.kind, endpoint.name, endpoint.status ]
        assert_equal 3, snapshot.resources.size, "a copy pipe is not an endpoint"
        assert_equal [ [ events.key, workspace.key, ResourceMap::RELATION_PART_OF ], [ endpoint.key, workspace.key, ResourceMap::RELATION_PART_OF ],
                       [ endpoint.key, events.key, ResourceMap::RELATION_USES ] ], snapshot.links.map { |link| [ link.from, link.to, link.relation ] }
        assert_empty snapshot.gaps
      end

      test "a region Tinybird documents no address for gets no link rather than a guessed one" do
        @integration.update!(settings: { Integration::REGION_SETTING => "gcp-northamerica-northeast2" })
        stub_queries("pipe_stats_rt" => [], "datasources_ops_log" => [], "jobs_log" => [])

        assert_nil Tinybird.new(@integration.reload).map_of(@row.reload).resources.first.url
        assert_no_match "Open this in", Tinybird.new(@integration).call("jobs", environment_row: @row, arguments: {})["content"].first["text"]
      end

      test "a list the map cannot read is a gap naming its kind, and unread statuses stay unknown" do
        TinybirdApi.any_instance.stubs(:pipes).raises(TinybirdApi::Refused, "Tinybird answered 403: not allowed")
        TinybirdApi.any_instance.stubs(:query).raises(TinybirdApi::Refused, "Tinybird answered 403: not allowed")

        snapshot = @pack.map_of(@row)

        assert_equal [ "analytics", "events" ], snapshot.resources.map(&:name)
        assert snapshot.resources.all? { |found| found.status.nil? }
        assert_includes snapshot.unread_kinds, ResourceMap::KIND_FUNCTION
        assert_includes snapshot.gap_texts, "Tinybird's pipes could not be read: Tinybird answered 403: not allowed."
      end

      test "an endpoint is quiet with no requests, failed when every request failed, and a 4xx alone does not degrade it" do
        assert_equal "ready", @pack.send(:endpoint_state, nil)
        assert_equal "failed", @pack.send(:endpoint_state, { "requests" => 4, "failed" => 4, "server_errors" => 0 })
        assert_equal "healthy", @pack.send(:endpoint_state, { "requests" => 4, "failed" => 2, "server_errors" => 0 })
        assert_equal "failed", @pack.send(:datasource_state, { "ok" => 0, "failed" => 2 })
        assert_equal "degraded", @pack.send(:datasource_state, { "ok" => 3, "failed" => 2 })
      end

      test "requests are read newest first for one endpoint, filtered in SQL with every value quoted, linked to the workspace" do
        TinybirdApi.any_instance.expects(:query).with do |sql|
          sql.include?("FROM tinybird.pipe_stats_rt") && sql.include?("(pipe_id = 'top_pages' OR pipe_name = 'top_pages')") &&
            sql.include?("start_datetime >= now() - INTERVAL 30 MINUTE") && sql.include?("ifNull(error_message, '')), 'it\\'s') > 0") &&
            sql.include?("AND error = 1") && sql.end_with?("ORDER BY start_datetime DESC LIMIT 200")
        end.returns("data" => [ { "at" => "2026-10-04 11:58:00", "pipe_name" => "top_pages", "status_code" => 400, "ms" => 12.5, "read_rows" => 10,
                                  "result_rows" => 0, "error" => 1, "message" => "[Error] Missing columns: 'x'", "address" => "/v0/pipes/top_pages.json?date_from=x",
                                  "token_name" => "web" } ])

        text = call(:endpoint_requests, "endpoint" => "top_pages", "text" => "it's", "failed_only" => true, "minutes" => 30)

        assert_match "1 log lines for requests to top_pages", text
        assert_match "2026-10-04T11:58:00Z top_pages HTTP 400, 12.5 ms, 10 rows read, 0 returned, token web, failed: [Error] Missing columns", text
        assert_match "link with what you found: #{SITE}", text
      end

      test "a request address has its token taken out by the query, and a filter never reads the token" do
        redacted = "replaceRegexpAll(url, '([?&])token=[^&]*', '\\\\1token=[REDACTED]')"
        TinybirdApi.any_instance.expects(:query).with do |sql|
          sql.include?("left(#{redacted}, 300) AS address") && sql.include?("positionCaseInsensitive(concat(#{redacted}, ' ', ifNull(error_message, '')), 'p.eyJ') > 0") &&
            sql.exclude?("left(url,")
        end.returns("data" => [])

        call(:endpoint_requests, "text" => "p.eyJ", "minutes" => 30)
      end

      test "data source operations name what ran, its result and the error" do
        TinybirdApi.any_instance.expects(:query).with { |sql| sql.include?("FROM tinybird.datasources_ops_log") && sql.include?("event_type = 'append'") }
                    .returns("data" => [ { "at" => "2026-10-04 11:00:00", "datasource_name" => "events", "event_type" => "append", "result" => "error",
                                           "seconds" => 0.4, "rows" => 0, "rows_quarantine" => 12, "pipe_name" => "", "message" => "Invalid JSON" } ])

        assert_match "events append, error, 0.4 s, 0 rows, 12 quarantined, Invalid JSON", call(:datasource_operations, "event_type" => "append")
      end

      test "errors come grouped across endpoints, data sources and jobs, most frequent first, and nothing failing is said" do
        TinybirdApi.any_instance.expects(:query).with { |sql| sql.include?("tinybird.endpoint_errors") && sql.include?("UNION ALL") && sql.include?("LIMIT 5") }
                    .returns("data" => [ { "source" => "endpoint", "name" => "top_pages", "message" => "HTTP 500, Memory limit exceeded", "times" => "7",
                                           "first_seen" => "2026-10-04 10:00:00", "last_seen" => "2026-10-04 11:00:00" } ])

        assert_match "endpoint top_pages: 7 times, first 2026-10-04 10:00:00, last 2026-10-04 11:00:00. HTTP 500, Memory limit exceeded", call(:list_errors, "limit" => 5)
        TinybirdApi.any_instance.stubs(:query).returns("data" => [])
        assert_match "Nothing failed for events in that range.", call(:list_errors, "name" => "events")
      end

      test "metrics are charts per minute and latency in milliseconds, for the asked endpoint, and a name the pack lacks is refused" do
        TinybirdApi.any_instance.expects(:query).with { |sql| sql.include?("INTERVAL 1 MINUTE) AS at") }.returns("data" => [
          { "at" => "2026-10-04 11:58:00", "requests" => "60", "errors" => "6", "latency_avg" => 0.02, "latency_p95" => 0.08 },
          { "at" => "2026-10-04 11:59:00", "requests" => "30", "errors" => "0", "latency_avg" => 0.01, "latency_p95" => 0.05 }
        ])

        result = @pack.call("endpoint_metrics", environment_row: @row, arguments: { "endpoint" => "top_pages", "minutes" => 60, "metrics" => %w[requests latency] })
        charts = result.dig(Telemetry::STRUCTURED, Telemetry::CHARTS)

        assert_equal [ "Requests of top_pages", "Latency of top_pages" ], charts.map { |chart| chart["title"] }
        assert_equal [ 60.0, 30.0 ], charts.first["series"].first["points"].map(&:last)
        assert_equal [ "average", "95th percentile" ], charts.last["series"].map { |series| series["label"] }
        assert_equal [ 80.0, 50.0 ], charts.last["series"].last["points"].map(&:last)
        assert_raises(NativePack::Error) { @pack.call("endpoint_metrics", environment_row: @row, arguments: { "metrics" => %w[memory] }) }
      end

      test "a read-only query runs as JSON and its rows are shown with what it read, and anything else is refused before Tinybird is asked" do
        TinybirdApi.any_instance.expects(:query).with("SELECT count() AS n FROM events").returns(
          "data" => [ { "n" => "1200" } ], "rows" => 1, "statistics" => { "rows_read" => 1200, "bytes_read" => 9600, "elapsed" => 0.002 }
        )

        assert_match "1 rows. Tinybird read 1200 rows, 9600 bytes, in 0.002 s.\nn: 1200", call(:run_query, "sql" => "SELECT count() AS n FROM events;")
        assert_raises(PolicyRefusal) { call(:run_query, "sql" => "INSERT INTO events VALUES (1)") }
        assert_raises(NativePack::Error) { call(:run_query, "sql" => "SELECT 1 FORMAT CSV") }
      end

      test "an endpoint is called with its parameters and its rows are cut to the limit" do
        TinybirdApi.any_instance.expects(:call_endpoint).with("top_pages", { "date_from" => "2026-10-01" })
                    .returns("data" => [ { "page" => "/a" }, { "page" => "/b" } ], "rows" => 2)

        text = call(:call_endpoint, "endpoint" => "top_pages", "params" => { "date_from" => "2026-10-01" }, "limit" => 1)

        assert_match "2 rows. Only the first 1 are shown", text
        assert_match "page: /a", text
        assert_no_match "/b", text
      end

      test "jobs are read newest first with their status and link to the workspace's jobs page" do
        TinybirdApi.any_instance.expects(:query).with { |sql| sql.include?("job_type = 'deployment'") && sql.include?("INTERVAL 7 DAY") }
                    .returns("data" => [ { "created_at" => "2026-10-04 09:00:00", "job_id" => "j9", "job_type" => "deployment", "pipe_name" => "",
                                           "status" => "error", "started_at" => "2026-10-04 09:00:05", "updated_at" => "2026-10-04 09:03:00",
                                           "message" => "Deployment failed", "metadata" => "{}" } ])

        text = call(:jobs, "job_type" => "deployment")

        assert_match "Latest 1 deployment jobs in the last 7 days", text
        assert_match "2026-10-04 09:00:00, deployment, error, job j9, started 2026-10-04 09:00:05, updated 2026-10-04 09:03:00, Deployment failed", text
        assert_match "#{SITE}/jobs", text
        assert_raises(NativePack::Error) { call(:jobs, "job_type" => "reboot") }
      end

      test "jobs carry when each started and ended as run history" do
        TinybirdApi.any_instance.stubs(:query).returns("data" => [
          { "created_at" => "2026-10-04 09:00:00", "job_id" => "j9", "job_type" => "populate", "pipe_name" => "top_products", "status" => "done",
            "started_at" => "2026-10-04 09:00:05", "updated_at" => "2026-10-04 09:03:05" },
          { "created_at" => "2026-10-04 10:00:00", "job_id" => "j10", "job_type" => "deployment", "pipe_name" => "", "status" => "working",
            "started_at" => "2026-10-04 10:00:01", "updated_at" => "2026-10-04 10:01:00" }
        ])

        result = @pack.call("jobs", environment_row: @row, arguments: {})

        assert_equal [ [ "j9", "populate top_products", "succeeded", 180 ], [ "j10", "deployment", "running", nil ] ],
                     Capabilities::History.runs_of(result).map { |run| [ run.id, run.name, run.status, run.seconds ] }
      end

      test "status reads the workspace, a data source or an endpoint by its name or id, and names what it does not know" do
        stub_queries("pipe_stats_rt" => [ { "pipe_id" => "t_top", "name" => "top_pages", "requests" => "40", "failed" => "3", "server_errors" => "2", "p95" => 0.2 } ],
                     "datasources_ops_log" => [ { "datasource_id" => "t_events", "name" => "events", "ok" => "1", "failed" => "2", "last_error" => "Invalid JSON" } ],
                     "jobs_log" => [])
        TinybirdApi.any_instance.stubs(:datasource).returns(EVENTS.merge("engine" => { "engine" => "MergeTree", "sorting_key" => "timestamp" }))
        TinybirdApi.any_instance.stubs(:pipe).returns(TOP_PAGES)

        workspace = call(:describe_resource, {})
        assert_match "Workspace analytics (id w-1) in Oregon, AWS (api.us-west-2.aws.tinybird.co), with 1 data sources, 1 API endpoints and 1 other pipes.", workspace
        assert_match "top_pages: 3 of 40 requests failed, 2 with a 5xx.", workspace
        assert_match "events: 2 failed, 1 succeeded. Latest error: Invalid JSON", workspace
        assert_match "events (id t_events), engine MergeTree, 1200 rows, 4096 bytes, read by top_pages", call(:describe_resource, "name" => "t_events")
        endpoint = call(:describe_resource, "name" => "top_pages")
        assert_match "It publishes node endpoint, of 2 nodes.", endpoint
        assert_match "Its parameters: date_from (Date, required).", endpoint
        assert_match "95% took under 200.0 ms", endpoint
        assert_raises(NativePack::Error) { call(:describe_resource, "name" => "missing") }
      end

      test "baselines read requests and failures hour by hour, an hour with none read as zero, for each endpoint and the workspace" do
        stub_queries("pipe_stats_rt" => [], "datasources_ops_log" => [], "jobs_log" => [])
        ResourceMap.record!(@row, @pack.map_of(@row))
        resources = ResourceMap::Resource.where(integration_environment: @row).to_a
        window = (Time.current - 3.hours)..Time.current
        TinybirdApi.any_instance.unstub(:query)
        TinybirdApi.any_instance.expects(:query).with { |sql| sql.include?("toStartOfHour(start_datetime)") && sql.include?("'2026-10-04 09:00:00'") }
                    .returns("data" => [ { "at" => "2026-10-04 10:00:00", "pipe_id" => "t_top", "requests" => "120", "errors" => "6" } ])

        found = @pack.baselines_of(@row, resources, window)
        endpoint = resources.find { |resource| resource.name == "top_pages" }
        requests = found.find { |reading| reading.key == endpoint.key && reading.metric == "requests" }

        assert_equal [ 0.0, 2.0, 0.0 ], requests.points.map(&:last)
        assert_equal [ "requests", "errors", "requests", "errors" ], found.map(&:metric)
        assert_equal "per minute", requests.unit
      end

      test "the health check reads the workspace and a service data source, and says why it cannot" do
        TinybirdApi.any_instance.expects(:query).with(Tinybird::HEALTH_QUERY).returns("data" => [])
        @pack.check_health!(@row)
        TinybirdApi.any_instance.stubs(:workspace).raises(TinybirdApi::Refused, "Tinybird answered 403: invalid authentication token")
        error = assert_raises(NativePack::Error) { Tinybird.new(@integration).check_health!(@row) }
        assert_equal "Tinybird answered 403: invalid authentication token", error.message
      end

      private

      def call(tool, arguments)
        @pack.call(tool.to_s, environment_row: @row, arguments: arguments)["content"].first["text"]
      end

      # Answers each service data source's query with its rows.
      def stub_queries(answers)
        answers.each do |table, rows|
          TinybirdApi.any_instance.stubs(:query).with { |sql| sql.include?("tinybird.#{table}") }.returns("data" => rows)
        end
      end
    end
  end
end
