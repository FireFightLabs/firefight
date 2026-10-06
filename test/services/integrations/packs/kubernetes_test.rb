require "test_helper"

module Integrations
  module Packs
    class KubernetesTest < ActiveSupport::TestCase
      include KubernetesTestHelper

      DEPLOYMENTS = "/apis/apps/v1/namespaces/production/deployments".freeze
      PODS = "/api/v1/namespaces/production/pods".freeze
      EVENTS = "/api/v1/namespaces/production/events".freeze
      REPLICA_SETS = "/apis/apps/v1/namespaces/production/replicasets".freeze

      setup do
        @workspace = workspaces(:slack_workspace_one)
        @integration = Integration.create!(workspace: @workspace, kind: Integration::KIND_NATIVE, provider: Kubernetes::PROVIDER_KEY, name: "Kubernetes")
        @row = @integration.integration_environments.create!
        @ca = kubernetes_ca_pem
        Kubernetes.store_credentials!(@row, Kubernetes::TOKEN => " sa-token ", Kubernetes::CA => @ca)
        @row.store_fields!(Kubernetes::SERVER => "https://cluster.example.com", Kubernetes::NAMESPACES => " production , production ")
        @pack = Kubernetes.new(@integration)
        PublicAddress.stubs(:resolve).returns(IPAddr.new("203.0.113.10"))
        KubernetesApi.any_instance.stubs(:get).raises(KubernetesApi::NotFound, "The API server answered 404: not found")
        KubernetesApi.any_instance.stubs(:list).returns(Pages::Read.new(items: [], complete: true))
        stub_get("#{DEPLOYMENTS}/web", deployment)
        stub_list(PODS, [ pod("web-old", "2026-10-04T09:00:00Z"), pod("web-new", "2026-10-04T11:00:00Z", crashing: true) ])
      end

      test "the token and CA are the only credentials, the address and namespaces are the registry's connect fields, and only the three changes write" do
        settings = ConnectionSettings.of(@row.reload)
        assert_equal "sa-token", settings.credential(Kubernetes::TOKEN)
        assert_equal [ Kubernetes::CA, Kubernetes::TOKEN ], @row.credentials_hash.keys.sort
        assert_equal [ Kubernetes::TOKEN, Kubernetes::CA ], Kubernetes.credential_fields.map(&:key)
        assert_equal [ Kubernetes::TOKEN ], Kubernetes.credential_fields.select(&:secret).map(&:key)
        assert_equal [ Kubernetes::CA ], Kubernetes.credential_fields.select(&:multiline).map(&:key)
        assert_equal [ Kubernetes::SERVER, Kubernetes::NAMESPACES ], IntegrationProvider.find(Kubernetes::PROVIDER_KEY).connect_fields.map(&:key)
        assert_equal %w[rollout_undo rollout_restart scale_workload], Kubernetes.tool_definitions.reject(&:read_only).map(&:name)
      end

      test "the registry refuses an address that is not https and namespaces that are not names, before the pack is asked" do
        server, namespaces = IntegrationProvider.find(Kubernetes::PROVIDER_KEY).connect_fields

        assert_nil server.refusal("https://cluster.example.com:6443")
        assert_nil server.refusal("https://rancher.example.com/k8s/clusters/c-1")
        assert_match "an https address", server.refusal("http://cluster.example.com")
        assert_nil namespaces.refusal("production, payments")
        assert_nil namespaces.refusal("*")
        [ "*, production", "Prod_1", "production," ].each { |value| assert_match "namespace names separated by commas, or * alone", namespaces.refusal(value) }
      end

      test "the form is refused with words for a missing value, an address or CA that cannot be used, and a token the cluster refuses" do
        values = { Kubernetes::TOKEN => "sa-token", Kubernetes::CA => @ca }
        fields = { Kubernetes::SERVER => "https://cluster.example.com", Kubernetes::NAMESPACES => "production" }
        refusal = ->(changed_values = {}, changed_fields = {}) { Kubernetes.credential_refusal(values.merge(changed_values), fields: fields.merge(changed_fields)) }

        assert_equal "Paste a service account token.", refusal.call(Kubernetes::TOKEN => " ")
        assert_equal "Enter the API server address.", refusal.call({}, Kubernetes::SERVER => "")
        assert_equal "Enter the namespaces, or * for every namespace.", refusal.call({}, Kubernetes::NAMESPACES => " ")
        assert_match "must start with https://", refusal.call({}, Kubernetes::SERVER => "http://cluster.example.com")
        assert_match "Paste certificate-authority-data from your kubeconfig", refusal.call(Kubernetes::CA => "nope")

        KubernetesApi.any_instance.stubs(:get).with(DEPLOYMENTS, "limit" => 1).returns("items" => [])
        assert_nil refusal.call
        KubernetesApi.any_instance.stubs(:get).with(DEPLOYMENTS, "limit" => 1).raises(KubernetesApi::Forbidden, "The API server answered 403: forbidden")
        assert_equal "The cluster refused this connection. The API server answered 403: forbidden.", refusal.call
        KubernetesApi.any_instance.stubs(:get).with("/apis/apps/v1/deployments", "limit" => 1).returns("items" => [])
        assert_nil refusal.call({}, Kubernetes::NAMESPACES => "*")
      end

      test "the health check lists in every connected namespace and fails with the cluster's words" do
        KubernetesApi.any_instance.stubs(:get).with(DEPLOYMENTS, "limit" => 1).returns("items" => [])
        assert_nothing_raised { @pack.check_health!(@row) }

        KubernetesApi.any_instance.stubs(:get).with(DEPLOYMENTS, "limit" => 1).raises(KubernetesApi::Error, "The API server answered 401: Unauthorized")
        assert_equal "The API server answered 401: Unauthorized", assert_raises(NativePack::Error) { @pack.check_health!(@row) }.message
      end

      test "a namespace the connection does not reach is refused, and a name alone finds its one workload" do
        assert_match "reaches only production, not payments", call_error(:describe_workload, "namespace" => "payments", "resource" => "deployment/web")
        assert_match "reaches only production, not payments", call_error(:describe_workload, "resource" => "payments/deployment/web")
        assert_match "No workload called api in production", call_error(:describe_workload, "resource" => "api")
        assert_match "deployment/web in production", call(:describe_workload, "resource" => "web")

        stub_get("/apis/apps/v1/namespaces/production/statefulsets/web", deployment)
        assert_equal "More than one Kubernetes resource is called web: deployment/web, statefulset/web. Name it by its id.",
                     call_error(:describe_workload, "resource" => "web")
      end

      test "logs come from the workload's pods, newest first, filtered and cut at the end, and the executor redacts anything credential-like" do
        KubernetesApi.any_instance.stubs(:text).with("#{PODS}/web-new/log", has_entries("container" => "web", "timestamps" => true, "tailLines" => Kubernetes::LOG_FETCH))
                     .returns("2026-10-04T11:58:00.123456789Z GET /checkout 500 timeout\n2026-10-04T11:59:00Z GET /up 200\n2026-10-04T13:00:00Z GET /checkout 500 after the end\n")
        KubernetesApi.any_instance.stubs(:text).with("#{PODS}/web-old/log", anything)
                     .returns("2026-10-04T11:57:00Z GET /checkout 500 token ghp_#{'a' * 36}\n")

        tool = @integration.tools.create!(name: "workload_logs", description: "Logs", read_only: true, enabled: true, params_schema: {})
        arguments = { "resource" => "deployment/web", "text" => "checkout", "start" => "2026-10-04T11:00:00Z", "end" => "2026-10-04T12:00:00Z" }
        text = NativeExecutor.call(tool: tool, environment_row: @row, arguments: arguments)["content"].first["text"]

        lines = text.lines.drop(1).map(&:strip)
        assert_match "2 log lines for deployment/web in production", text
        assert_equal "2026-10-04T11:58:00Z web-new/web GET /checkout 500 timeout", lines.first
        assert_match "token [REDACTED:github_token]", lines.second
        assert_no_match "after the end", text
        assert_no_match "/up", text
        assert_match "regex could not be read", call_error(:workload_logs, "resource" => "deployment/web", "regex" => "(")
      end

      test "previous reads each container before its last restart, and one that has none is said, not failed" do
        KubernetesApi.any_instance.stubs(:text).with("#{PODS}/web-new/log", has_entry("previous" => true)).returns("2026-10-04T11:58:00Z panic: out of memory\n")
        KubernetesApi.any_instance.stubs(:text).with("#{PODS}/web-old/log", has_entry("previous" => true))
                     .raises(KubernetesApi::Error, "The API server answered 400: previous terminated container \"web\" not found")

        text = call(:workload_logs, "resource" => "deployment/web", "previous" => true, "start" => "2026-10-04T11:00:00Z", "end" => "2026-10-04T12:00:00Z")

        assert_match "panic: out of memory", text
        assert_match "run: kubectl logs -l 'app=web' -n production --timestamps --since-time=2026-10-04T11:00:00Z --previous", text
        assert_match "web-old/web has no earlier container to read", text
      end

      test "metrics are the metrics API's current reading against requests and limits, and a cluster without it is told" do
        stub_list("/apis/metrics.k8s.io/v1beta1/namespaces/production/pods", [
          { "metadata" => { "name" => "web-new" }, "timestamp" => "2026-10-04T12:00:00Z", "window" => "30s",
            "containers" => [ { "name" => "web", "usage" => { "cpu" => "500000000n", "memory" => "393216Ki" } } ] }
        ])

        text = call(:pod_metrics, "resource" => "deployment/web")

        assert_match "read at 2026-10-04T12:00:00Z", text
        assert_match "web-new: CPU 0.5 cores (request 0.25 cores, limit 1.0 cores), memory 384.0 MiB (request 256.0 MiB, limit 512.0 MiB)", text
        assert_match "web-old: no reading yet (Running)", text
        assert_match "not a history", text

        KubernetesApi.any_instance.stubs(:list).with { |path, *| path.start_with?("/apis/metrics.k8s.io") }.raises(KubernetesApi::NotFound, "404")
        assert_match "no metrics API", call_error(:pod_metrics, "resource" => "deployment/web")
      end

      test "a workload's state shows replicas, conditions, containers, why pods stopped and its events, never an environment value" do
        stub_list(EVENTS, [
          { "type" => "Warning", "reason" => "BackOff", "message" => "Back-off restarting failed container web", "count" => 12,
            "lastTimestamp" => "2026-10-04T11:59:00Z", "involvedObject" => { "kind" => "Pod", "name" => "web-new" } },
          { "type" => "Warning", "reason" => "FailedMount", "message" => "unrelated", "lastTimestamp" => "2026-10-04T11:59:30Z",
            "involvedObject" => { "kind" => "Pod", "name" => "worker-1" } }
        ])

        text = call(:describe_workload, "resource" => "deployment/web")

        assert_match "Replicas: 3 desired, 2 ready, 3 up to date, 2 available, 1 unavailable", text
        assert_match "Available False, MinimumReplicasUnavailable", text
        assert_match "web: ghcr.io/acme/web:v3, requests cpu 250m memory 256Mi, limits cpu 1 memory 512Mi, liveness probe HTTP /up port 3000", text
        assert_match "web waiting: CrashLoopBackOff", text
        assert_match "last stopped: OOMKilled, exit code 137", text
        assert_match "BackOff pod/web-new: Back-off restarting failed container web (12 times)", text
        assert_no_match "unrelated", text
        assert_no_match "hunter2", text
      end

      test "the rollout history is the deployment's replica sets by revision, marking the current one" do
        stub_list(REPLICA_SETS, replica_sets)

        text = call(:rollout_history, "resource" => "deployment/web")

        assert_equal [ "Revisions of deployment/web in production, newest first.",
                       "revision 3, 2026-10-03T10:00:00Z, current, images ghcr.io/acme/web:v3, change cause deploy v3",
                       "revision 2, 2026-10-02T10:00:00Z, images ghcr.io/acme/web:v2",
                       "There is no Kubernetes page to link to. To check this at the source, run: kubectl rollout history deployment/web -n production" ],
                     text.lines.map(&:strip)
      end

      test "a deployment goes back to a revision the way kubectl rollout undo does, and refuses a paused one" do
        stub_list(REPLICA_SETS, replica_sets)
        KubernetesApi.any_instance.expects(:patch).with("#{DEPLOYMENTS}/web", anything, KubernetesApi::PATCH_JSON).with do |_path, patch, _type|
          template, annotations = patch.map { |operation| operation["value"] }
          patch.map { |operation| [ operation["op"], operation["path"] ] } == [ %w[replace /spec/template], %w[replace /metadata/annotations] ] &&
            template.dig("metadata", "labels") == { "app" => "web" } && template.dig("spec", "containers", 0, "image") == "ghcr.io/acme/web:v2" &&
            annotations == { Kubernetes::REVISION => "3", "kubectl.kubernetes.io/last-applied-configuration" => "{}", "team" => "checkout" }
        end.returns({})

        assert_match "going back to revision 2 (images ghcr.io/acme/web:v2)", call(:rollout_undo, "resource" => "deployment/web", "revision" => 2)
        assert_match "already runs revision 3", call(:rollout_undo, "resource" => "deployment/web", "revision" => 3)
        assert_match "has no revision 9", call_error(:rollout_undo, "resource" => "deployment/web", "revision" => 9)

        stub_get("#{DEPLOYMENTS}/web", deployment.deep_merge("spec" => { "paused" => true }))
        assert_match "is paused", call_error(:rollout_undo, "resource" => "deployment/web", "revision" => 2)
      end

      test "a statefulset goes back by applying its controller revision as a strategic merge patch" do
        set = deployment.deep_merge("metadata" => { "name" => "db", "uid" => "sts-uid" })
        stub_get("/apis/apps/v1/namespaces/production/statefulsets/db", set)
        data = { "spec" => { "template" => { "$patch" => "replace", "spec" => { "containers" => [ { "name" => "db", "image" => "postgres:16" } ] } } } }
        stub_list("/apis/apps/v1/namespaces/production/controllerrevisions", [
          { "metadata" => { "name" => "db-1", "creationTimestamp" => "2026-10-01T10:00:00Z", "ownerReferences" => [ { "controller" => true, "uid" => "sts-uid" } ] }, "revision" => 1, "data" => data },
          { "metadata" => { "name" => "db-2", "creationTimestamp" => "2026-10-02T10:00:00Z", "ownerReferences" => [ { "controller" => true, "uid" => "sts-uid" } ] }, "revision" => 2, "data" => {} }
        ])
        KubernetesApi.any_instance.expects(:patch).with("/apis/apps/v1/namespaces/production/statefulsets/db", data, KubernetesApi::PATCH_STRATEGIC).returns({})

        assert_match "statefulset/db in production is going back to revision 1 (images postgres:16)", call(:rollout_undo, "resource" => "statefulset/db", "revision" => 1)
        assert_match "revision 2, 2026-10-02T10:00:00Z, current", call(:rollout_history, "resource" => "statefulset/db")
      end

      test "a restart stamps the pod template as kubectl rollout restart does, and only a rolling workload restarts" do
        travel_to Time.utc(2026, 10, 4, 12, 0, 0) do
          KubernetesApi.any_instance.expects(:patch)
                       .with("#{DEPLOYMENTS}/web", { "spec" => { "template" => { "metadata" => { "annotations" => { Kubernetes::RESTARTED_AT => "2026-10-04T12:00:00Z" } } } } }, KubernetesApi::PATCH_STRATEGIC)
                       .returns({})

          assert_match "is restarting as of 2026-10-04T12:00:00Z", call(:rollout_restart, "resource" => "deployment/web")
        end

        stub_get("/apis/batch/v1/namespaces/production/cronjobs/nightly", { "metadata" => { "name" => "nightly", "uid" => "cj" }, "spec" => { "schedule" => "0 3 * * *" } })
        assert_match "cannot be restarted this way", call_error(:rollout_restart, "resource" => "cronjob/nightly")
      end

      test "scaling patches the scale subresource, names an autoscaler that will move it back, and says what the role lacks" do
        stub_list("/apis/autoscaling/v2/namespaces/production/horizontalpodautoscalers", [
          { "metadata" => { "name" => "web-hpa" }, "spec" => { "scaleTargetRef" => { "kind" => "Deployment", "name" => "web" } } }
        ])
        KubernetesApi.any_instance.expects(:patch).with("#{DEPLOYMENTS}/web/scale", { "spec" => { "replicas" => 5 } }, KubernetesApi::PATCH_MERGE).returns({})

        text = call(:scale_workload, "resource" => "deployment/web", "replicas" => 5)
        assert_match "now asks for 5 pods, it asked for 3. The autoscaler web-hpa also sets its replicas", text

        KubernetesApi.any_instance.stubs(:patch).raises(KubernetesApi::Forbidden, "The API server answered 403: forbidden")
        assert_match "Give it patch on deployments/scale in production", call_error(:scale_workload, "resource" => "deployment/web", "replicas" => 1)
        stub_get("/apis/apps/v1/namespaces/production/daemonsets/agent", deployment)
        assert_match "cannot be scaled", call_error(:scale_workload, "resource" => "daemonset/agent", "replicas" => 1)
      end

      test "a resource's labels are kept in its details for finding it by, and one with none leaves the key out" do
        reading = Kubernetes::MapReading.new("cluster.example.com")
        reading.add(Kubernetes::WORKLOADS.fetch(Kubernetes::DEPLOYMENT), deployment.deep_merge("metadata" => { "labels" => { "app" => "web", "team" => "payments" } }))
        reading.add(Kubernetes::WORKLOADS.fetch(Kubernetes::DEPLOYMENT), deployment.deep_merge("metadata" => { "name" => "worker" }))

        assert_equal({ "app" => "web", "team" => "payments" }, reading.resources.first.details[ResourceMap::TAGS])
        assert_not reading.resources.last.details.key?(ResourceMap::TAGS)
      end

      test "the map holds the workloads, services and ingresses with what serves what, and a list it may not read is a gap" do
        stub_list(DEPLOYMENTS, [ deployment ])
        stub_list("/apis/batch/v1/namespaces/production/cronjobs", [ { "metadata" => { "name" => "nightly", "namespace" => "production" }, "spec" => { "schedule" => "0 3 * * *" } } ])
        stub_list("/apis/batch/v1/namespaces/production/jobs", [
          { "metadata" => { "name" => "nightly-1", "namespace" => "production", "ownerReferences" => [ { "kind" => "CronJob", "controller" => true } ] } },
          { "metadata" => { "name" => "migrate", "namespace" => "production" }, "status" => { "conditions" => [ { "type" => "Complete", "status" => "True" } ] } }
        ])
        stub_list("/api/v1/namespaces/production/services", [
          { "metadata" => { "name" => "web", "namespace" => "production" }, "spec" => { "type" => "LoadBalancer", "selector" => { "app" => "web" } },
            "status" => { "loadBalancer" => { "ingress" => [ { "hostname" => "lb.example.net" } ] } } }
        ])
        stub_list("/apis/networking.k8s.io/v1/namespaces/production/ingresses", [
          { "metadata" => { "name" => "web", "namespace" => "production" },
            "spec" => { "rules" => [ { "host" => "shop.example.com", "http" => { "paths" => [ { "backend" => { "service" => { "name" => "web" } } } ] } }, { "host" => "*.example.com" } ] } }
        ])
        KubernetesApi.any_instance.stubs(:list).with("/apis/apps/v1/namespaces/production/daemonsets").raises(KubernetesApi::Forbidden, "The API server answered 403: forbidden")

        snapshot = @pack.map_of(@row)

        named = snapshot.resources.to_h { |found| [ found.external_id, found ] }
        assert_equal [ "production/deployment/web", "production/cronjob/nightly", "production/job/migrate", "production/service/web",
                       "lb.example.net", "production/ingress/web", "shop.example.com" ].sort, named.keys.sort
        web = named.fetch("production/deployment/web")
        assert_equal [ ResourceMap::KIND_SERVICE, "cluster.example.com/production", "progressing" ], [ web.kind, web.account, web.status ]
        assert_equal({ "type" => "Deployment", "namespace" => "production", "instances" => 3, "images" => "ghcr.io/acme/web:v3" }, web.details)
        assert_equal ResourceMap::KIND_LOAD_BALANCER, named.fetch("production/service/web").kind
        assert_equal "succeeded", named.fetch("production/job/migrate").status
        served = snapshot.links.map { |link| [ link.from.last, link.to.last ] }
        assert_equal [ [ "production/service/web", "production/deployment/web" ], [ "lb.example.net", "production/service/web" ],
                       [ "production/ingress/web", "production/service/web" ], [ "shop.example.com", "production/ingress/web" ] ], served
        assert_equal [ ResourceMap::Gap.new(text: "Daemonsets in production could not be read: The API server answered 403: forbidden.", kinds: [ ResourceMap::KIND_SERVICE ]) ],
                     snapshot.gaps
        assert_equal [ ResourceMap::KIND_SERVICE ], snapshot.unread_kinds
        assert_equal %w[active active], [ named.fetch("production/service/web").status, named.fetch("production/ingress/web").status ]
        assert_equal "pending", Kubernetes.state_of(Kubernetes::SERVICE.key, { "spec" => { "type" => "LoadBalancer" }, "status" => {} })
      end

      test "a workload whose rollout finished but whose pods are no longer ready reads degraded, and one still rolling out progressing" do
        complete = [ { "type" => "Progressing", "status" => "True", "reason" => "NewReplicaSetAvailable" } ]
        rolling = [ { "type" => "Progressing", "status" => "True", "reason" => "ReplicaSetUpdated" } ]
        deployment = ->(ready, conditions) { { "spec" => { "replicas" => 3 }, "status" => { "readyReplicas" => ready, "updatedReplicas" => 3, "conditions" => conditions } } }

        assert_equal "running", Kubernetes.state_of(Kubernetes::DEPLOYMENT, deployment.(3, complete))
        assert_equal "degraded", Kubernetes.state_of(Kubernetes::DEPLOYMENT, deployment.(1, complete))
        assert_equal "progressing", Kubernetes.state_of(Kubernetes::DEPLOYMENT, deployment.(1, rolling))
        assert_equal "degraded", Kubernetes.state_of(Kubernetes::STATEFULSET, { "spec" => { "replicas" => 2 }, "status" => { "readyReplicas" => 1, "currentRevision" => "a", "updateRevision" => "a" } })
        assert_equal "progressing", Kubernetes.state_of(Kubernetes::STATEFULSET, { "spec" => { "replicas" => 2 }, "status" => { "readyReplicas" => 1, "currentRevision" => "a", "updateRevision" => "b" } })
        assert_equal "degraded", Kubernetes.state_of(Kubernetes::DAEMONSET, { "status" => { "desiredNumberScheduled" => 3, "numberReady" => 2, "updatedNumberScheduled" => 3 } })
        assert_equal ResourceMap::Resource::HEALTH_FAILING, ResourceMap::Resource.new(status: Provider.for("kubernetes").status_of("degraded")).health
      end

      test "a service or ingress list that could not be read holds back the hostnames they put on the map too" do
        KubernetesApi.any_instance.stubs(:list).returns(Pages::Read.new(items: [], complete: true))
        KubernetesApi.any_instance.stubs(:list).with { |asked, *| asked == "/api/v1/namespaces/production/services" }.raises(KubernetesApi::Forbidden, "The API server answered 403: forbidden")
        KubernetesApi.any_instance.stubs(:list).with { |asked, *| asked == "/apis/networking.k8s.io/v1/namespaces/production/ingresses" }
                     .returns(Pages::Read.new(items: [], complete: false))

        snapshot = @pack.map_of(@row)

        assert_equal [ ResourceMap::KIND_LOAD_BALANCER, ResourceMap::KIND_DOMAIN ], snapshot.unread_kinds
        assert_equal 2, snapshot.gaps.size
        assert(snapshot.gaps.all? { |gap| gap.kinds == [ ResourceMap::KIND_LOAD_BALANCER, ResourceMap::KIND_DOMAIN ] })
      end

      test "the namespace's resources are listed with their state, leaving out a cronjob's own jobs, and a list it may not read is said" do
        stub_list(DEPLOYMENTS, [ deployment ])
        stub_list("/apis/batch/v1/namespaces/production/jobs", [
          { "metadata" => { "name" => "nightly-1", "namespace" => "production", "ownerReferences" => [ { "kind" => "CronJob" } ] } }
        ])
        stub_list("/api/v1/namespaces/production/services", [
          { "metadata" => { "name" => "web", "namespace" => "production" }, "spec" => { "selector" => { "app" => "web" }, "ports" => [ { "port" => 80, "targetPort" => 3000 } ] } }
        ])
        KubernetesApi.any_instance.stubs(:list).with("/apis/networking.k8s.io/v1/namespaces/production/ingresses").raises(KubernetesApi::Forbidden, "The API server answered 403: forbidden")

        text = call(:list_resources)

        assert_equal [ "2 resources in production.", "deployment/web in production: 2 of 3 ready, progressing",
                       "service/web in production: ClusterIP, ports 80 to 3000, selects app=web",
                       "Ingresses in production could not be listed: The API server answered 403: forbidden.",
                       "There is no Kubernetes page to link to. To check this at the source, run: kubectl get " \
                       "deployments,statefulsets,daemonsets,cronjobs,jobs,services,ingresses -n production" ], text.lines.map(&:strip)
      end

      test "events are the namespace's warnings about what was asked, newest first" do
        stub_list(EVENTS, [
          { "type" => "Warning", "reason" => "FailedScheduling", "message" => "0/3 nodes are available: 3 Insufficient cpu.",
            "lastTimestamp" => "2026-10-04T11:00:00Z", "involvedObject" => { "kind" => "Pod", "name" => "web-new" } },
          { "type" => "Normal", "reason" => "Scheduled", "message" => "assigned", "lastTimestamp" => "2026-10-04T11:30:00Z",
            "involvedObject" => { "kind" => "Pod", "name" => "web-new" } },
          { "type" => "Warning", "reason" => "BackOff", "message" => "restarting", "eventTime" => "2026-10-04T11:45:00.000000Z",
            "series" => { "count" => 3, "lastObservedTime" => "2026-10-04T11:50:00Z" }, "involvedObject" => { "kind" => "Pod", "name" => "worker-1" } }
        ])

        assert_equal [ "2 events in production, newest first.",
                       "2026-10-04T11:50:00Z Warning BackOff pod/worker-1: restarting (3 times)",
                       "2026-10-04T11:00:00Z Warning FailedScheduling pod/web-new: 0/3 nodes are available: 3 Insufficient cpu.",
                       "There is no Kubernetes page to link to. To check this at the source, run: kubectl get events -n production " \
                       "--sort-by=.lastTimestamp --field-selector type=Warning" ],
                     call(:list_events).lines.map(&:strip)
        about_web = call(:list_events, "resource" => "deployment/web", "type" => "all")
        assert_match "2 events in production", about_web
        assert_match "Normal Scheduled pod/web-new", about_web
        assert_no_match "worker-1", about_web
        assert_match "No Warning events in production about api", call(:list_events, "resource" => "api")
      end

      test "a cronjob shows its schedule, last runs and recent jobs, and its pods are its newest job's" do
        cronjob = { "metadata" => { "name" => "nightly", "namespace" => "production", "uid" => "cj-uid", "creationTimestamp" => "2026-09-01T00:00:00Z" },
                    "spec" => { "schedule" => "0 3 * * *", "timeZone" => "Etc/UTC", "concurrencyPolicy" => "Forbid",
                                "jobTemplate" => { "spec" => { "template" => { "spec" => { "containers" => [ { "name" => "task", "image" => "acme/task:1" } ] } } } } },
                    "status" => { "lastScheduleTime" => "2026-10-04T03:00:00Z", "lastSuccessfulTime" => "2026-10-02T03:00:00Z" } }
        stub_get("/apis/batch/v1/namespaces/production/cronjobs/nightly", cronjob)
        owner = [ { "controller" => true, "uid" => "cj-uid" } ]
        stub_list("/apis/batch/v1/namespaces/production/jobs", [
          { "metadata" => { "name" => "nightly-2", "creationTimestamp" => "2026-10-03T03:00:00Z", "ownerReferences" => owner }, "spec" => { "selector" => { "matchLabels" => { "job" => "2" } } },
            "status" => { "startTime" => "2026-10-03T03:00:00Z", "conditions" => [ { "type" => "Failed", "status" => "True", "reason" => "BackoffLimitExceeded" } ] } },
          { "metadata" => { "name" => "nightly-3", "creationTimestamp" => "2026-10-04T03:00:00Z", "ownerReferences" => owner },
            "spec" => { "selector" => { "matchLabels" => { "job" => "3" }, "matchExpressions" => [ { "key" => "tier", "operator" => "NotIn", "values" => %w[a b] } ] } },
            "status" => { "startTime" => "2026-10-04T03:00:00Z" } }
        ])
        KubernetesApi.any_instance.expects(:list).with(PODS, "labelSelector" => "job=3,tier notin (a,b)").returns(Pages::Read.new(items: [], complete: true))

        text = call(:describe_workload, "resource" => "cronjob/nightly")

        assert_match "Schedule: 0 3 * * * Etc/UTC, concurrency Forbid", text
        assert_match "Last scheduled 2026-10-04T03:00:00Z, last succeeded 2026-10-02T03:00:00Z, 0 running now", text
        assert_match "nightly-3: running, started 2026-10-04T03:00:00Z\n  nightly-2: failed (BackoffLimitExceeded)", text
        assert_match "task: acme/task:1, no requests or limits, no probes", text
      end

      test "a sweep the cluster refuses outright fails, so the map is left as it was" do
        KubernetesApi.any_instance.stubs(:list).raises(KubernetesApi::Error, "The API server answered 401: Unauthorized")

        assert_raises(KubernetesApi::Error) { @pack.map_of(@row) }
      end

      private

      def call(tool, arguments = {})
        @pack.call(tool.to_s, environment_row: @row, arguments: arguments)["content"].first["text"]
      end

      def call_error(tool, arguments)
        assert_raises(NativePack::Error) { call(tool, arguments) }.message
      end

      def stub_get(path, body) = KubernetesApi.any_instance.stubs(:get).with(path).returns(body)

      def stub_list(path, items)
        KubernetesApi.any_instance.stubs(:list).with { |asked, *| asked == path }.returns(Pages::Read.new(items: items, complete: true))
      end

      def deployment
        {
          "metadata" => { "name" => "web", "namespace" => "production", "uid" => "dep-uid", "creationTimestamp" => "2026-10-01T10:00:00Z",
                          "annotations" => { Kubernetes::REVISION => "3", "kubectl.kubernetes.io/last-applied-configuration" => "{}" } },
          "spec" => {
            "replicas" => 3, "selector" => { "matchLabels" => { "app" => "web" } },
            "template" => {
              "metadata" => { "labels" => { "app" => "web" } },
              "spec" => { "containers" => [ {
                "name" => "web", "image" => "ghcr.io/acme/web:v3", "env" => [ { "name" => "DATABASE_URL", "value" => "postgres://app:hunter2@db/prod" } ],
                "resources" => { "requests" => { "cpu" => "250m", "memory" => "256Mi" }, "limits" => { "cpu" => "1", "memory" => "512Mi" } },
                "livenessProbe" => { "httpGet" => { "path" => "/up", "port" => 3000 }, "periodSeconds" => 10, "failureThreshold" => 3 }
              } ] }
            }
          },
          "status" => {
            "replicas" => 3, "readyReplicas" => 2, "updatedReplicas" => 3, "availableReplicas" => 2, "unavailableReplicas" => 1,
            "conditions" => [ { "type" => "Available", "status" => "False", "reason" => "MinimumReplicasUnavailable", "message" => "Deployment does not have minimum availability." } ]
          }
        }
      end

      def pod(name, created, crashing: false)
        status = { "name" => "web", "ready" => !crashing, "restartCount" => crashing ? 4 : 0 }
        if crashing
          status["state"] = { "waiting" => { "reason" => "CrashLoopBackOff", "message" => "back-off 5m0s restarting failed container" } }
          status["lastState"] = { "terminated" => { "reason" => "OOMKilled", "exitCode" => 137, "finishedAt" => "2026-10-04T11:58:00Z" } }
        end
        {
          "metadata" => { "name" => name, "creationTimestamp" => created },
          "spec" => { "nodeName" => "node-1", "containers" => deployment.dig("spec", "template", "spec", "containers") },
          "status" => { "phase" => "Running", "startTime" => created, "containerStatuses" => [ status ] }
        }
      end

      def replica_sets
        owner = [ { "controller" => true, "uid" => "dep-uid" } ]
        [
          { "metadata" => { "name" => "web-2", "creationTimestamp" => "2026-10-02T10:00:00Z", "ownerReferences" => owner,
                            "annotations" => { Kubernetes::REVISION => "2", "team" => "checkout" } },
            "spec" => { "template" => { "metadata" => { "labels" => { "app" => "web", Kubernetes::POD_TEMPLATE_HASH => "abc" } },
                                        "spec" => { "containers" => [ { "name" => "web", "image" => "ghcr.io/acme/web:v2" } ] } } } },
          { "metadata" => { "name" => "web-3", "creationTimestamp" => "2026-10-03T10:00:00Z", "ownerReferences" => owner,
                            "annotations" => { Kubernetes::REVISION => "3", Kubernetes::CHANGE_CAUSE => "deploy v3" } },
            "spec" => { "template" => { "metadata" => { "labels" => { "app" => "web" } }, "spec" => { "containers" => [ { "name" => "web", "image" => "ghcr.io/acme/web:v3" } ] } } } },
          { "metadata" => { "name" => "other", "annotations" => { Kubernetes::REVISION => "7" }, "ownerReferences" => [ { "controller" => true, "uid" => "someone-else" } ] } }
        ]
      end
    end
  end
end
