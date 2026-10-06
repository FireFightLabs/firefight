require "test_helper"

module Integrations
  module MapEventSources
    class KubernetesTest < ActiveSupport::TestCase
      include KubernetesTestHelper

      DEPLOYMENTS = "/apis/apps/v1/namespaces/production/deployments".freeze

      setup do
        @workspace = workspaces(:slack_workspace_one)
        integration = Integration.create!(workspace: @workspace, kind: Integration::KIND_NATIVE, provider: "kubernetes", name: "Kubernetes")
        @row = integration.integration_environments.create!
        Packs::Kubernetes.store_credentials!(@row, Packs::Kubernetes::TOKEN => "sa-token", Packs::Kubernetes::CA => kubernetes_ca_pem)
        @row.store_fields!(Packs::Kubernetes::SERVER => "https://cluster.example.com", Packs::Kubernetes::NAMESPACES => "production")
        PublicAddress.stubs(:resolve).returns(IPAddr.new("203.0.113.10"))
        KubernetesApi.any_instance.stubs(:get).with { |_path, query = {}| query == { "limit" => 1 } }.returns("metadata" => { "resourceVersion" => "100" })
        KubernetesApi.any_instance.stubs(:watch)
      end

      test "the first read takes each list's version and follows from there, every two minutes" do
        KubernetesApi.any_instance.expects(:watch).never

        polled = Kubernetes.poll(@row, since: nil)

        assert_empty polled.events
        assert_equal Packs::Kubernetes::MAPPED.to_h { |kind| [ "production/#{kind.plural}", "100" ] }, JSON.parse(polled.cursor)
        assert_equal 2.minutes, Kubernetes.poll_every
      end

      test "a watched change names the one object it is about, a bookmark moves the version, and a Job its CronJob made is left out" do
        changed = { "type" => "MODIFIED", "object" => { "metadata" => { "name" => "web", "namespace" => "production", "uid" => "u1", "resourceVersion" => "120" } } }
        deleted = { "type" => "DELETED", "object" => { "metadata" => { "name" => "old", "namespace" => "production", "uid" => "u2", "resourceVersion" => "130",
                                                                        "deletionTimestamp" => "2026-10-06T10:00:00Z" } } }
        bookmark = { "type" => "BOOKMARK", "object" => { "metadata" => { "resourceVersion" => "150" } } }
        made = { "type" => "ADDED", "object" => { "metadata" => { "name" => "nightly-1", "namespace" => "production", "uid" => "u3", "resourceVersion" => "140",
                                                                   "ownerReferences" => [ { "kind" => "CronJob" } ] } } }
        KubernetesApi.any_instance.stubs(:watch).with(DEPLOYMENTS, resource_version: "100").multiple_yields([ changed ], [ deleted ], [ bookmark ])
        KubernetesApi.any_instance.stubs(:watch).with("/apis/batch/v1/namespaces/production/jobs", resource_version: "100").multiple_yields([ made ])

        polled = Kubernetes.poll(@row, since: cursor)

        assert_equal [ [ "u1@120", ResourceMap::Event::UPDATED, "production/deployment/web" ], [ "u2@130", ResourceMap::Event::REMOVED, "production/deployment/old" ] ],
                     polled.events.map { |event| [ event.id, event.action, event.scope.external_id ] }
        assert_equal [ "cluster.example.com/production", ResourceMap::KIND_SERVICE ], [ polled.events.first.scope.account, polled.events.first.scope.kind ]
        assert_equal Time.iso8601("2026-10-06T10:00:00Z"), polled.events.last.at
        assert_equal "150", JSON.parse(polled.cursor)["production/deployments"]
        assert_equal "140", JSON.parse(polled.cursor)["production/jobs"], "a change left out still moves the version"
      end

      test "a list whose version the server no longer keeps is read in full once, and starts again from now" do
        KubernetesApi.any_instance.stubs(:watch).with(DEPLOYMENTS, resource_version: "100").raises(KubernetesApi::Gone, "The API server answered 410: too old")
        KubernetesApi.any_instance.stubs(:get).with(DEPLOYMENTS, "limit" => 1).returns("metadata" => { "resourceVersion" => "900" })

        polled = Kubernetes.poll(@row, since: cursor)

        assert polled.events.sole.scope.everything?
        assert_equal "900", JSON.parse(polled.cursor)["production/deployments"]
      end

      test "a token whose role may not watch is refused with what to allow, and any other failure is raised" do
        KubernetesApi.any_instance.stubs(:watch).with(DEPLOYMENTS, resource_version: "100").raises(KubernetesApi::Forbidden, "The API server answered 403: forbidden")

        refused = assert_raises(MapEventSource::Refused) { Kubernetes.poll(@row, since: cursor) }
        assert_equal "The token's role may not watch deployments in production, which following changes as they happen needs. Allow watch beside get " \
                     "and list on what Firefight reads.", refused.message

        KubernetesApi.any_instance.stubs(:watch).with(DEPLOYMENTS, resource_version: "100").raises(KubernetesApi::Error, "could not reach cluster.example.com")
        assert_raises(KubernetesApi::Error) { Kubernetes.poll(@row, since: cursor) }
      end

      private

      def cursor = Packs::Kubernetes::MAPPED.to_h { |kind| [ "production/#{kind.plural}", "100" ] }.to_json
    end
  end
end
