require "test_helper"

module Integrations
  module MapEventSources
    class GoogleCloudTest < ActiveSupport::TestCase
      KEY = { "type" => "service_account", "client_email" => "firefight@acme-prod.iam.gserviceaccount.com", "private_key" => "pem" }.to_json

      setup do
        @workspace = workspaces(:slack_workspace_one)
        @integration = Integration.create!(workspace: @workspace, kind: Integration::KIND_NATIVE, provider: "google_cloud", name: "Google Cloud")
        @row = @integration.integration_environments.create!
        Packs::GoogleCloud.store_credentials!(@row, Packs::GoogleCloud::KEY => KEY)
        @row.store_fields!(Packs::GoogleCloud::PROJECT => "acme-prod")
      end

      test "the first read starts from now and asks Google nothing" do
        GoogleCloudApi.any_instance.expects(:log_entries_since).never

        travel_to Time.zone.parse("2026-10-06T12:00:00Z") do
          polled = GoogleCloud.poll(@row, since: nil)
          assert_empty polled.events
          assert_equal({ "acme-prod" => "2026-10-06T12:00:00.000000Z" }, JSON.parse(polled.cursor))
        end
      end

      test "a read asks for the project's Admin Activity log from before the cursor, and each entry names the resource the map keeps" do
        filter = nil
        GoogleCloudApi.any_instance.expects(:log_entries_since).with { |project, asked| project == "acme-prod" && (filter = asked) }.returns(Pages::Read.new(items: [
          entry("e1", "run.googleapis.com", "google.cloud.run.v2.Services.UpdateService", "projects/acme-prod/locations/us-central1/services/web",
                labels: { "service_name" => "web", "location" => "us-central1" }),
          entry("e2", "cloudsql.googleapis.com", "cloudsql.instances.restart", "projects/acme-prod/instances/orders",
                labels: { "database_id" => "acme-prod:orders", "region" => "us-central1" }),
          entry("e3", "compute.googleapis.com", "v1.compute.instances.delete", "projects/acme-prod/zones/us-central1-a/instances/worker-1"),
          entry("e4", "container.googleapis.com", "google.container.v1.ClusterManager.CreateCluster", "projects/acme-prod/zones/europe-west1-b/clusters/apps",
                labels: { "cluster_name" => "apps", "location" => "europe-west1-b" }),
          entry("e5", "run.googleapis.com", "google.cloud.run.v1.Jobs.CreateJob", "namespaces/acme-prod/jobs/nightly", labels: { "job_name" => "nightly" }),
          entry("e6", "cloudsql.googleapis.com", "cloudsql.instances.update", "projects/acme-prod/instances/ledger", labels: { "database_id" => "acme-prod:ledger" })
        ], complete: true))

        polled = travel_to(Time.zone.parse("2026-10-06T12:05:00Z")) { GoogleCloud.poll(@row, since: "2026-10-06T12:00:00.000000Z") }

        assert_equal 'logName="projects/acme-prod/logs/cloudaudit.googleapis.com%2Factivity" AND timestamp>="2026-10-06T11:50:00.000000Z" AND ' \
                     'protoPayload.serviceName=("run.googleapis.com" OR "cloudsql.googleapis.com" OR "compute.googleapis.com" OR "container.googleapis.com")', filter
        assert_equal({ "acme-prod" => "2026-10-06T12:05:00.000000Z" }, JSON.parse(polled.cursor), "a cursor from before is the project's")
        assert_equal %w[e1 e2 e3 e4 e6], polled.events.map(&:id)
        assert_equal [
          [ ResourceMap::KIND_SERVICE, "projects/acme-prod/locations/us-central1/services/web", ResourceMap::Event::UPDATED ],
          [ ResourceMap::KIND_DATABASE, "acme-prod:us-central1:orders", ResourceMap::Event::UPDATED ],
          [ ResourceMap::KIND_VIRTUAL_MACHINE, "projects/acme-prod/zones/us-central1-a/instances/worker-1", ResourceMap::Event::REMOVED ],
          [ ResourceMap::KIND_CLUSTER, "projects/acme-prod/locations/europe-west1-b/clusters/apps", ResourceMap::Event::ADDED ],
          [ ResourceMap::KIND_DATABASE, nil, ResourceMap::Event::UPDATED ]
        ], polled.events.map { |event| [ event.scope.kind, event.scope.external_id, event.action ] }
        assert_equal [ "acme-prod" ], polled.events.map { |event| event.scope.account }.uniq
        assert_equal Time.iso8601("2026-10-06T12:01:00Z"), polled.events.first.at
      end

      test "a read cut short continues from its last entry, and a key the log refuses is the provider's words" do
        GoogleCloudApi.any_instance.stubs(:log_entries_since).returns(Pages::Read.new(items: [
          entry("e1", "compute.googleapis.com", "v1.compute.instances.stop", "projects/acme-prod/zones/us-central1-a/instances/worker-1", at: "2026-10-06T12:02:30Z")
        ], complete: false))
        assert_equal "2026-10-06T12:02:30.000000Z", JSON.parse(GoogleCloud.poll(@row, since: "2026-10-06T12:00:00Z").cursor)["acme-prod"]

        GoogleCloudApi.any_instance.stubs(:log_entries_since).returns(Pages::Read.new(items: [], complete: false))
        assert_equal "2026-10-06T12:00:00.000000Z", JSON.parse(GoogleCloud.poll(@row, since: "2026-10-06T12:00:00Z").cursor)["acme-prod"],
                     "pages still searching with no entries keep the cursor where it was"

        GoogleCloudApi.any_instance.stubs(:log_entries_since).raises(GoogleCloudApi::Forbidden, "Google Cloud answered 403: Permission denied")
        assert_raises(GoogleCloudApi::Forbidden) { GoogleCloud.poll(@row, since: "2026-10-06T12:00:00Z") }
      end

      test "each project is read from its own cursor, a new one from now, and one the key cannot read leaves the others read" do
        @row.store_fields!(Packs::GoogleCloud::PROJECT => %w[acme-prod acme-staging acme-new])
        GoogleCloudApi.any_instance.expects(:log_entries_since).with { |project, asked| project == "acme-prod" && asked.include?("11:50:00") }
                      .returns(Pages::Read.new(items: [ entry("p1", "compute.googleapis.com", "v1.compute.instances.stop", "projects/acme-prod/zones/a/instances/w") ], complete: true))
        GoogleCloudApi.any_instance.expects(:log_entries_since).with { |project, _| project == "acme-staging" }
                      .raises(GoogleCloudApi::Forbidden, "Google Cloud answered 403: Permission denied")
        cursor = { "acme-prod" => "2026-10-06T12:00:00.000000Z", "acme-staging" => "2026-10-06T11:00:00.000000Z" }.to_json

        polled = travel_to(Time.zone.parse("2026-10-06T12:05:00Z")) { GoogleCloud.poll(@row, since: cursor) }

        assert_equal [ "acme-prod" ], polled.events.map { |event| event.scope.account }
        assert_equal({ "acme-staging" => "2026-10-06T11:00:00.000000Z", "acme-prod" => "2026-10-06T12:05:00.000000Z", "acme-new" => "2026-10-06T12:05:00.000000Z" },
                     JSON.parse(polled.cursor))
        assert_equal "The change log of project acme-staging could not be read: Google Cloud answered 403: Permission denied.", polled.error
      end

      private

      def entry(id, service, method, name, labels: {}, at: "2026-10-06T12:01:00Z")
        { "insertId" => id, "timestamp" => at, "resource" => { "labels" => labels },
          "protoPayload" => { "serviceName" => service, "methodName" => method, "resourceName" => name } }
      end
    end
  end
end
