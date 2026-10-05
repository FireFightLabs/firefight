require "test_helper"

module Integrations
  module Packs
    class GoogleCloudTest < ActiveSupport::TestCase
      RUN_ID = "projects/acme-prod/locations/us-central1/services/web".freeze
      SQL_ID = "acme-prod:us-central1:orders".freeze
      VM_ID = "projects/acme-prod/zones/us-central1-a/instances/worker-1".freeze
      KEY = { "type" => "service_account", "client_email" => "firefight@acme-prod.iam.gserviceaccount.com", "private_key" => "pem" }.to_json
      SERVICE = {
        "name" => RUN_ID, "uri" => "https://web-abc-uc.a.run.app", "urls" => [ "https://web-123.us-central1.run.app" ], "etag" => "e1",
        "latestReadyRevision" => "#{RUN_ID}/revisions/web-00002-xyz", "latestCreatedRevision" => "#{RUN_ID}/revisions/web-00002-xyz",
        "terminalCondition" => { "type" => "Ready", "state" => "CONDITION_SUCCEEDED" }, "scaling" => { "minInstanceCount" => 1, "maxInstanceCount" => 10 },
        "template" => { "containers" => [ { "image" => "us-docker.pkg.dev/acme/web:v2" } ] },
        "trafficStatuses" => [ { "type" => "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST", "percent" => 100 } ]
      }.freeze

      setup do
        @workspace = workspaces(:slack_workspace_one)
        @integration = Integration.create!(workspace: @workspace, kind: Integration::KIND_NATIVE, provider: "google_cloud", name: "Google Cloud")
        @row = @integration.integration_environments.create!
        GoogleCloud.store_credentials!(@row, GoogleCloud::KEY => " #{KEY} ")
        @row.store_fields!(GoogleCloud::PROJECT => "acme-prod")
        @pack = GoogleCloud.new(@integration)
        GoogleCloudApi.any_instance.stubs(:run_locations).returns(pages([ { "locationId" => "us-central1" } ]))
        GoogleCloudApi.any_instance.stubs(:run_services).returns(pages([ SERVICE ]))
        GoogleCloudApi.any_instance.stubs(:run_service).returns(SERVICE)
        GoogleCloudApi.any_instance.stubs(:sql_instances).returns(pages([
          { "name" => "orders", "connectionName" => SQL_ID, "region" => "us-central1", "state" => "RUNNABLE", "databaseVersion" => "POSTGRES_16",
            "settings" => { "tier" => "db-custom-2-7680", "availabilityType" => "REGIONAL" } }
        ]))
        GoogleCloudApi.any_instance.stubs(:compute_instances).returns(pages([
          { "id" => "4242", "name" => "worker-1", "status" => "RUNNING", "zone" => "https://www.googleapis.com/compute/v1/projects/acme-prod/zones/us-central1-a",
            "selfLink" => "https://www.googleapis.com/compute/v1/#{VM_ID}", "machineType" => ".../machineTypes/e2-medium" }
        ]))
        GoogleCloudApi.any_instance.stubs(:clusters).returns(reached([ { "name" => "apps", "location" => "europe-west1", "status" => "RUNNING", "currentMasterVersion" => "1.33" } ]))
      end

      test "only the key is a credential, stored trimmed with the token minted before dropped, and only the three changes are not read only" do
        @row.store_credential!(GoogleCloudApi::TOKEN_CACHE_KEY, { "token" => "old" })
        GoogleCloud.store_credentials!(@row, GoogleCloud::KEY => KEY)

        assert_equal({ GoogleCloud::KEY => KEY }, @row.reload.credentials_hash.compact)
        assert_equal [ GoogleCloud::KEY ], GoogleCloud.credential_fields.map(&:key)
        assert_equal %w[rollback_service scale_service restart_resource], GoogleCloud.tool_definitions.reject(&:read_only).map(&:name)
      end

      test "a key or project Google refuses is said before anything is saved" do
        GoogleCloudApi.any_instance.stubs(:project).raises(GoogleCloudApi::Error, "Google Cloud answered 403: The caller does not have permission")

        assert_match "Google Cloud refused this key or project: Google Cloud answered 403", GoogleCloud.credential_refusal({ GoogleCloud::KEY => KEY }, fields: { GoogleCloud::PROJECT => "acme-prod" })
        assert_equal "Paste the service account's JSON key.", GoogleCloud.credential_refusal({}, fields: { GoogleCloud::PROJECT => "acme-prod" })
        assert_equal "Enter the project id.", GoogleCloud.credential_refusal({ GoogleCloud::KEY => KEY })
        assert_match "not JSON", GoogleCloud.credential_refusal({ GoogleCloud::KEY => "nope" }, fields: { GoogleCloud::PROJECT => "acme-prod" })
      end

      test "every product's resources are listed, and one Google refuses is named rather than failing the list" do
        GoogleCloudApi.any_instance.stubs(:clusters).raises(GoogleCloudApi::Forbidden, "Google Cloud answered 403: Kubernetes Engine API has not been used")

        text = call(:list_resources)

        assert_match "web (#{RUN_ID}), Cloud Run service in us-central1, ready", text
        assert_match "orders (#{SQL_ID}), Cloud SQL instance in us-central1, runnable", text
        assert_match "worker-1 (#{VM_ID}), Compute Engine instance in us-central1-a, running", text
        assert_match "Not listed: GKE clusters could not be read: Google Cloud answered 403", text
        assert_match "https://console.cloud.google.com/run/services?project=acme-prod", text
      end

      test "a Cloud Run service's logs are read by its labels, newest first, with every filter quoted, and link to its revision's logs" do
        GoogleCloudApi.any_instance.expects(:log_entries).with do |project, filter, limit:|
          project == "acme-prod" && limit == 50 && filter.include?('resource.type="cloud_run_revision" AND resource.labels.service_name="web"') &&
            filter.include?('NOT log_id("run.googleapis.com/requests")') && filter.include?('SEARCH("say \"hi\"")') &&
            filter.include?('textPayload=~"time.?out"') && filter.include?('NOT SEARCH("health")')
        end.returns([ { "timestamp" => "2026-10-03T10:00:00Z", "severity" => "ERROR", "textPayload" => "upstream timed out",
                        "resource" => { "labels" => { "revision_name" => "web-00002-xyz" } } } ])
        GoogleCloudApi.any_instance.stubs(:get).returns({ "logUri" => "https://console.cloud.google.com/logs/viewer?revision=web-00002-xyz" })

        text = call(:search_logs, "resource" => "web", "text" => 'say "hi"', "regex" => "time.?out", "exclude" => "health", "limit" => 50)

        assert_match "2026-10-03T10:00:00Z web-00002-xyz ERROR upstream timed out", text
        assert_match "link with what you found: https://console.cloud.google.com/logs/viewer?revision=web-00002-xyz", text
      end

      test "request logs are only a Cloud Run service's, and say each request's method, address, status and latency" do
        GoogleCloudApi.any_instance.expects(:log_entries).with { |_, filter, **| filter.include?('AND log_id("run.googleapis.com/requests")') }
                      .returns([ { "timestamp" => "2026-10-03T10:00:00Z", "httpRequest" => { "requestMethod" => "GET", "requestUrl" => "https://web/x", "status" => 503, "latency" => "30.1s" } } ])
        GoogleCloudApi.any_instance.stubs(:get).raises(GoogleCloudApi::Error, "nope")

        assert_match "GET https://web/x 503 30.1s", call(:search_logs, "resource" => RUN_ID, "stream" => "requests")
        assert_match "Only a Cloud Run service keeps request logs", assert_raises(Integrations::Error) { call(:search_logs, "resource" => "orders", "stream" => "requests") }.message
      end

      test "metrics are read from Cloud Monitoring per kind, a fraction shown as a percentage, and a metric a kind lacks is refused" do
        queries = []
        GoogleCloudApi.any_instance.stubs(:time_series).with { |_, query| queries << query }.returns([
          { "points" => [ { "interval" => { "endTime" => "2026-10-03T10:01:00Z" }, "value" => { "doubleValue" => 0.5 } },
                          { "interval" => { "endTime" => "2026-10-03T10:00:00Z" }, "value" => { "doubleValue" => 0.25 } } ] }
        ])

        result = @pack.call("query_metrics", environment_row: @row, arguments: { "resource" => "web", "metrics" => [ "cpu" ], "minutes" => 60 })

        assert_equal 'metric.type="run.googleapis.com/container/cpu/utilizations" AND resource.type="cloud_run_revision" AND ' \
                     'resource.labels.service_name="web" AND resource.labels.location="us-central1"', queries.first["filter"]
        assert_equal [ "ALIGN_PERCENTILE_99", "REDUCE_MAX", "60s" ], queries.first.values_at("aggregation.perSeriesAligner", "aggregation.crossSeriesReducer", "aggregation.alignmentPeriod")
        chart = result.dig(Telemetry::STRUCTURED, Telemetry::CHARTS).first
        assert_equal [ 25.0, 50.0 ], chart["series"].first["points"].map(&:last)
        assert_equal "%", chart["unit"]
        assert_match "A Compute Engine instance has no disk", assert_raises(Integrations::Error) { call(:query_metrics, "resource" => VM_ID, "metrics" => [ "disk" ]) }.message
      end

      test "a PostgreSQL instance's connections are its backends, and a MySQL one's its network connections" do
        GoogleCloudApi.any_instance.stubs(:sql_instance).returns({ "databaseVersion" => "POSTGRES_16" })
        GoogleCloudApi.any_instance.expects(:time_series).with { |_, query| query["filter"].include?("database/postgresql/num_backends") && query["filter"].include?('database_id="acme-prod:orders"') }.returns([])

        assert_match "Connections of orders: no data", call(:query_metrics, "resource" => SQL_ID, "metrics" => [ "tcp_connections" ])
      end

      test "revisions show who made them, the image and their share of the traffic" do
        GoogleCloudApi.any_instance.stubs(:run_revisions).returns([
          { "name" => "#{RUN_ID}/revisions/web-00001-abc", "createTime" => "2026-10-01T09:00:00Z", "containers" => [ { "image" => "web:v1" } ],
            "conditions" => [ { "type" => "Ready", "state" => "CONDITION_SUCCEEDED" } ] },
          { "name" => "#{RUN_ID}/revisions/web-00002-xyz", "createTime" => "2026-10-03T09:00:00Z", "creator" => "ana@acme.dev",
            "containers" => [ { "image" => "web:v2" } ], "conditions" => [ { "type" => "Ready", "state" => "CONDITION_SUCCEEDED" } ] }
        ])

        text = call(:list_revisions, "resource" => "web")

        assert_match "2026-10-03T09:00:00Z, web-00002-xyz, by ana@acme.dev, image web:v2, ready succeeded, 100% of traffic\n" \
                     "2026-10-01T09:00:00Z, web-00001-abc, image web:v1, ready succeeded, 0% of traffic", text
      end

      test "errors are asked of Error Reporting for the service over the shortest period that covers the range, and filtered by text" do
        GoogleCloudApi.any_instance.expects(:error_group_stats).with do |project, query|
          project == "acme-prod" && query == { "serviceFilter.service" => "web", "timeRange.period" => "PERIOD_6_HOURS", "order" => "COUNT_DESC", "pageSize" => 20 }
        end.returns([
          { "count" => "42", "firstSeenTime" => "2026-10-03T08:00:00Z", "lastSeenTime" => "2026-10-03T10:00:00Z", "group" => { "resolutionStatus" => "OPEN" },
            "representative" => { "message" => "TimeoutError: upstream\n  at handler" } },
          { "count" => "3", "representative" => { "message" => "KeyError" } }
        ])

        text = call(:error_groups, "resource" => "web", "minutes" => 120, "text" => "timeout")

        assert_match "1 kind of error from web in the last 6 hours, most frequent first.\n42 times, first 2026-10-03T08:00:00Z, last 2026-10-03T10:00:00Z, open, TimeoutError: upstream", text
        assert_match "https://console.cloud.google.com/errors?project=acme-prod", text
      end

      test "a rollback sends all traffic to a revision the service has, and says where it went before" do
        GoogleCloudApi.any_instance.stubs(:run_revisions).returns([ { "name" => "#{RUN_ID}/revisions/web-00001-abc" } ])
        GoogleCloudApi.any_instance.expects(:update_run_service).with do |project, location, name, body, **|
          [ project, location, name ] == %w[acme-prod us-central1 web] && body["etag"] == "e1" &&
            body["traffic"] == [ { "type" => GoogleCloud::REVISION_TRAFFIC, "revision" => "web-00001-abc", "percent" => 100 } ]
        end.returns({ "name" => "projects/acme-prod/locations/us-central1/operations/op-1" })

        text = call(:rollback_service, "resource" => "web", "revision" => "web-00001-abc")

        assert text.start_with?("Google Cloud is sending all of web's traffic to revision web-00001-abc as operation op-1. Before, it went 100% to web-00002-xyz.")
        assert_match "has no revision called web-9", assert_raises(Integrations::Error) { call(:rollback_service, "resource" => "web", "revision" => "web-9") }.message
      end

      test "scaling sets the service's own limits by field mask, and refuses a minimum above the maximum or a service scaled by hand" do
        GoogleCloudApi.any_instance.expects(:update_run_service).with { |*, body, update_mask:| body == { "scaling" => { "minInstanceCount" => 3 } } && update_mask == "scaling.minInstanceCount" }.returns({})

        assert_match "Google Cloud is setting web to at least 3 instances. Before, it was at least 1 instance and at most 10.", call(:scale_service, "resource" => "web", "min_instances" => 3)
        assert_match "min_instances (12) cannot be above max_instances (10)", assert_raises(Integrations::Error) { call(:scale_service, "resource" => "web", "min_instances" => 12) }.message
        GoogleCloudApi.any_instance.stubs(:run_service).returns(SERVICE.merge("scaling" => { "scalingMode" => "MANUAL", "manualInstanceCount" => 4 }))
        assert_match "manual scaling at 4 instances", assert_raises(Integrations::Error) { call(:scale_service, "resource" => "web", "min_instances" => 2) }.message
      end

      test "a Cloud SQL instance restarts, a Compute Engine instance resets, and a Cloud Run service has no restart" do
        GoogleCloudApi.any_instance.expects(:restart_sql_instance).with("acme-prod", "orders").returns({})
        GoogleCloudApi.any_instance.expects(:reset_compute_instance).with("acme-prod", "us-central1-a", "worker-1").returns({})

        assert_match "restarting Cloud SQL instance orders", call(:restart_resource, "resource" => SQL_ID)
        assert_match "what was in its memory is gone", call(:restart_resource, "resource" => VM_ID)
        assert_match "has no restart", assert_raises(Integrations::Error) { call(:restart_resource, "resource" => "web") }.message
      end

      test "a resource in another project is never reached, and a name is found on the map before the live list" do
        GoogleCloudApi.any_instance.expects(:restart_sql_instance).never
        assert_match "is in project other, and this connection reaches acme-prod",
                     assert_raises(Integrations::Error) { call(:restart_resource, "resource" => "other:us-central1:orders") }.message

        ResourceMap::Resource.create!(workspace: @workspace, provider: "google_cloud", account: "acme-prod", kind: ResourceMap::KIND_DATABASE, external_id: SQL_ID,
                                      name: "Orders", integration_environment: @row, first_seen_at: Time.current, last_seen_at: Time.current)
        GoogleCloudApi.any_instance.expects(:sql_instances).never
        GoogleCloudApi.any_instance.stubs(:sql_instance).returns({ "name" => "orders", "databaseVersion" => "POSTGRES_16", "region" => "us-central1", "state" => "RUNNABLE" })
        assert_match "orders, a Cloud SQL POSTGRES_16 instance in us-central1, runnable", call(:describe_resource, "resource" => "orders")
      end

      test "the project goes on the map with the addresses its services serve, and a product it cannot read takes nothing away" do
        GoogleCloudApi.any_instance.stubs(:compute_instances).raises(GoogleCloudApi::Forbidden, "Google Cloud answered 403: Compute Engine API has not been used")

        snapshot = @pack.map_of(@row)

        web = snapshot.resources.find { |resource| resource.external_id == RUN_ID }
        assert_equal [ ResourceMap::KIND_SERVICE, "web", "ready", "https://console.cloud.google.com/run/services?project=acme-prod" ], [ web.kind, web.name, web.status, web.url ]
        assert_equal({ "type" => "Cloud Run service", "region" => "us-central1", "image" => "us-docker.pkg.dev/acme/web:v2", "latest_revision" => "web-00002-xyz" }, web.details)
        assert_equal %w[web-123.us-central1.run.app web-abc-uc.a.run.app], snapshot.links.map { |link| link.from.last }.sort
        assert snapshot.links.all? { |link| link.to == web.key && link.relation == ResourceMap::RELATION_SERVED_BY }
        assert_includes snapshot.resources.map(&:kind), ResourceMap::KIND_CLUSTER
        assert_equal [ ResourceMap::KIND_VIRTUAL_MACHINE ], snapshot.unread_kinds
        assert_match "Compute Engine instances could not be read", snapshot.gap_texts.first
      end

      test "a zone Google Cloud could not reach is a gap, so its machines and clusters are not taken as gone" do
        GoogleCloudApi.any_instance.stubs(:compute_instances).returns(reached([], unreachable: [ "us-east1-b" ]))
        GoogleCloudApi.any_instance.stubs(:clusters).returns(reached([], unreachable: [ "europe-west1-c" ]))

        snapshot = @pack.map_of(@row)

        assert_equal [ ResourceMap::KIND_VIRTUAL_MACHINE, ResourceMap::KIND_CLUSTER ], snapshot.unread_kinds
        assert_includes snapshot.gap_texts, "Google Cloud could not reach us-east1-b, so the Compute Engine instances there were not read."
        assert_includes snapshot.gap_texts, "Google Cloud could not reach europe-west1-c, so the GKE clusters there were not read."
      end

      test "a Cloud Run list that could not be read holds back the addresses its services serve, and a stopped Cloud SQL instance reads stopped" do
        GoogleCloudApi.any_instance.stubs(:run_locations).raises(GoogleCloudApi::Forbidden, "Google Cloud answered 403: Cloud Run Admin API has not been used")
        GoogleCloudApi.any_instance.stubs(:sql_instances).returns(pages([
          { "name" => "orders", "connectionName" => SQL_ID, "region" => "us-central1", "state" => "RUNNABLE", "settings" => { "activationPolicy" => "NEVER" } }
        ]))

        snapshot = @pack.map_of(@row)

        assert_equal [ ResourceMap::KIND_SERVICE, ResourceMap::KIND_DOMAIN ], snapshot.unread_kinds
        assert_equal "stopped", snapshot.resources.find { |resource| resource.external_id == SQL_ID }.status
      end

      test "two resources of one name are refused rather than one chosen, and a list cut short is a gap with its kind unread" do
        other = SERVICE.merge("name" => "projects/acme-prod/locations/europe-west1/services/web")
        GoogleCloudApi.any_instance.stubs(:run_locations).returns(pages([ { "locationId" => "us-central1" }, { "locationId" => "europe-west1" } ]))
        GoogleCloudApi.any_instance.stubs(:run_services).with("acme-prod", "us-central1").returns(pages([ SERVICE ]))
        GoogleCloudApi.any_instance.stubs(:run_services).with("acme-prod", "europe-west1").returns(pages([ other ]))

        assert_match "More than one Google Cloud resource is called web", assert_raises(Integrations::Error) { call(:describe_resource, "resource" => "web") }.message

        GoogleCloudApi.any_instance.stubs(:sql_instances).returns(pages([ { "name" => "orders", "connectionName" => SQL_ID, "state" => "ONLINE_MAINTENANCE" } ], complete: false))
        snapshot = GoogleCloud.new(@integration).map_of(@row)
        assert_includes snapshot.gap_texts, "Only the first 1 Cloud SQL instances were read."
        assert_equal [ ResourceMap::KIND_DATABASE ], snapshot.unread_kinds
        status = snapshot.resources.find { |resource| resource.external_id == SQL_ID }.status
        assert_equal [ "online_maintenance", "pending" ], [ status, Integrations::Providers::GoogleCloud.status_of(status) ]
      end

      test "a week of readings becomes a baseline per metric, with a rate per second read per minute" do
        resource = ResourceMap::Resource.create!(workspace: @workspace, provider: "google_cloud", account: "acme-prod", kind: ResourceMap::KIND_SERVICE, external_id: RUN_ID,
                                                 name: "web", integration_environment: @row, first_seen_at: Time.current, last_seen_at: Time.current)
        GoogleCloudApi.any_instance.stubs(:time_series).returns([ { "points" => [ { "interval" => { "endTime" => "2026-10-03T10:00:00Z" }, "value" => { "doubleValue" => 2.0 } } ] } ])

        found = @pack.baselines_of(@row, [ resource ], 7.days.ago..Time.current)

        requests = found.find { |reading| reading.metric == "requests" }
        assert_equal [ "per minute", 120.0 ], [ requests.unit, requests.points.first.last ]
        assert_equal %w[requests http_5xx cpu memory], found.map(&:metric)
      end

      test "the health check reads the project" do
        GoogleCloudApi.any_instance.expects(:project).with("acme-prod").returns({ "projectId" => "acme-prod" })
        @pack.check_health!(@row)

        GoogleCloudApi.any_instance.stubs(:project).raises(GoogleCloudApi::Error, "Google answered 400: invalid_grant")
        assert_raises(NativePack::Error) { @pack.check_health!(@row) }
      end

      private

      def pages(items, complete: true) = Integrations::Pages::Read.new(items: items, complete: complete)

      def reached(items, unreachable: []) = GoogleCloudApi::Reached.new(items: items, complete: unreachable.empty?, unreachable: unreachable)

      def call(tool, arguments = {})
        GoogleCloud.new(@integration).call(tool.to_s, environment_row: @row, arguments: arguments)["content"].map { |part| part["text"] }.join("\n")
      end
    end
  end
end
