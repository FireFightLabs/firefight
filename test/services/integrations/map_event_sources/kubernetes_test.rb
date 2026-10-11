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
        assert_equal [ *Packs::Kubernetes::MAPPED, Packs::Kubernetes::WARNINGS ].to_h { |kind| [ "production/#{kind.plural}", "100" ] }, JSON.parse(polled.cursor)
        assert_equal 2.minutes, Kubernetes.poll_every
      end

      test "a watched change names the one object it is about, a bookmark moves the version, and a Job its CronJob made is the CronJob's" do
        changed = { "type" => "MODIFIED", "object" => { "metadata" => { "name" => "web", "namespace" => "production", "uid" => "u1", "resourceVersion" => "120" } } }
        deleted = { "type" => "DELETED", "object" => { "metadata" => { "name" => "old", "namespace" => "production", "uid" => "u2", "resourceVersion" => "130",
                                                                        "deletionTimestamp" => "2026-10-06T10:00:00Z" } } }
        bookmark = { "type" => "BOOKMARK", "object" => { "metadata" => { "resourceVersion" => "150" } } }
        made = { "type" => "ADDED", "object" => { "metadata" => { "name" => "nightly-1", "namespace" => "production", "uid" => "u3", "resourceVersion" => "140",
                                                                   "ownerReferences" => [ { "kind" => "CronJob", "name" => "nightly" } ] } } }
        orphan = { "type" => "ADDED", "object" => { "metadata" => { "name" => "odd-1", "namespace" => "production", "uid" => "u4", "resourceVersion" => "141",
                                                                     "ownerReferences" => [ { "kind" => "CronJob" } ] } } }
        KubernetesApi.any_instance.stubs(:watch).with(DEPLOYMENTS, resource_version: "100").multiple_yields([ changed ], [ deleted ], [ bookmark ])
        KubernetesApi.any_instance.stubs(:watch).with("/apis/batch/v1/namespaces/production/jobs", resource_version: "100").multiple_yields([ made ], [ orphan ])

        polled = Kubernetes.poll(@row, since: cursor)

        assert_equal [ [ "u1@120", ResourceMap::Event::UPDATED, "production/deployment/web" ], [ "u2@130", ResourceMap::Event::REMOVED, "production/deployment/old" ],
                       [ "u3@140", ResourceMap::Event::UPDATED, "production/cronjob/nightly" ] ],
                     polled.events.map { |event| [ event.id, event.action, event.scope.external_id ] }
        assert_equal [ "cluster.example.com/production", ResourceMap::KIND_SERVICE ], [ polled.events.first.scope.account, polled.events.first.scope.kind ]
        assert_equal Time.iso8601("2026-10-06T10:00:00Z"), polled.events.second.at
        assert_equal "150", JSON.parse(polled.cursor)["production/deployments"]
        assert_equal "141", JSON.parse(polled.cursor)["production/jobs"], "a change left out still moves the version"
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

      test "a warning wakes the workload it is about, found through its pod's and replica set's owners, and each object is read once" do
        warning = lambda do |uid, version, kind, name, type: "Warning"|
          { "type" => "ADDED", "object" => { "type" => type, "reason" => "BackOff", "metadata" => { "uid" => uid, "resourceVersion" => version, "namespace" => "production" },
                                             "involvedObject" => { "kind" => kind, "name" => name, "namespace" => "production" } } }
        end
        KubernetesApi.any_instance.stubs(:watch).with("/api/v1/namespaces/production/events", resource_version: "100", query: { "fieldSelector" => "type=Warning" })
                     .multiple_yields([ warning.call("e1", "201", "Pod", "web-7d9-abcde") ], [ warning.call("e1", "202", "Pod", "web-7d9-abcde") ],
                                      [ warning.call("e2", "203", "StatefulSet", "db") ], [ warning.call("e3", "204", "Pod", "gone-1") ],
                                      [ warning.call("e4", "205", "Job", "nightly-29") ], [ warning.call("e5", "206", "Pod", "web-7d9-abcde", type: "Normal") ])
        KubernetesApi.any_instance.expects(:get).with("/api/v1/namespaces/production/pods/web-7d9-abcde").once
                     .returns("metadata" => { "ownerReferences" => [ { "kind" => "ReplicaSet", "name" => "web-7d9", "controller" => true } ] })
        KubernetesApi.any_instance.expects(:get).with("/apis/apps/v1/namespaces/production/replicasets/web-7d9").once
                     .returns("metadata" => { "ownerReferences" => [ { "kind" => "Deployment", "name" => "web", "controller" => true } ] })
        KubernetesApi.any_instance.stubs(:get).with("/api/v1/namespaces/production/pods/gone-1").raises(KubernetesApi::NotFound, "The API server answered 404: not found")
        KubernetesApi.any_instance.stubs(:get).with("/apis/batch/v1/namespaces/production/jobs/nightly-29")
                     .returns("metadata" => { "ownerReferences" => [ { "kind" => "CronJob", "name" => "nightly", "controller" => true } ] })

        polled = Kubernetes.poll(@row, since: cursor)

        assert_equal [ [ "warning:e1@201", "production/deployment/web" ], [ "warning:e1@202", "production/deployment/web" ], [ "warning:e2@203", "production/statefulset/db" ],
                       [ "warning:e4@205", "production/cronjob/nightly" ] ],
                     polled.events.map { |event| [ event.id, event.scope.external_id ] }
        assert(polled.events.all? { |event| event.action == ResourceMap::Event::UPDATED })
        assert_equal "206", JSON.parse(polled.cursor)["production/events"]
      end

      test "a token that may not watch events still follows the rest, and events the server no longer keeps start again from now without a sweep" do
        events = "/api/v1/namespaces/production/events"
        KubernetesApi.any_instance.stubs(:watch).with(events, resource_version: "100", query: { "fieldSelector" => "type=Warning" })
                     .raises(KubernetesApi::Forbidden, "The API server answered 403: forbidden")
        assert_empty Kubernetes.poll(@row, since: cursor).events

        KubernetesApi.any_instance.stubs(:watch).with(events, resource_version: "100", query: { "fieldSelector" => "type=Warning" })
                     .raises(KubernetesApi::Gone, "The API server answered 410: too old")
        KubernetesApi.any_instance.stubs(:get).with(events, "limit" => 1).returns("metadata" => { "resourceVersion" => "700" })
        polled = Kubernetes.poll(@row, since: cursor)
        assert_empty polled.events
        assert_equal "700", JSON.parse(polled.cursor)["production/events"]
      end

      private

      def cursor = [ *Packs::Kubernetes::MAPPED, Packs::Kubernetes::WARNINGS ].to_h { |kind| [ "production/#{kind.plural}", "100" ] }.to_json
    end
  end
end
