require "test_helper"

# Fixtures follow the Kubernetes API reference's shapes for Deployment, ReplicaSet, StatefulSet, ControllerRevision,
# CronJob, Job and Pod.
module Integrations
  module Packs
    class KubernetesRunsTest < ActiveSupport::TestCase
      include KubernetesTestHelper

      DEPLOYMENTS = "/apis/apps/v1/namespaces/production/deployments".freeze
      STATEFULSETS = "/apis/apps/v1/namespaces/production/statefulsets".freeze
      REPLICA_SETS = "/apis/apps/v1/namespaces/production/replicasets".freeze
      REVISIONS = "/apis/apps/v1/namespaces/production/controllerrevisions".freeze
      CRONJOBS = "/apis/batch/v1/namespaces/production/cronjobs".freeze
      JOBS = "/apis/batch/v1/namespaces/production/jobs".freeze
      PODS = "/api/v1/namespaces/production/pods".freeze
      History = Capabilities::History

      setup do
        @workspace = workspaces(:slack_workspace_one)
        @integration = Integration.create!(workspace: @workspace, kind: Integration::KIND_NATIVE, provider: Kubernetes::PROVIDER_KEY, name: "Kubernetes")
        @row = @integration.integration_environments.create!
        Kubernetes.store_credentials!(@row, Kubernetes::TOKEN => "sa-token", Kubernetes::CA => kubernetes_ca_pem)
        @row.store_fields!(Kubernetes::SERVER => "https://cluster.example.com", Kubernetes::NAMESPACES => "production")
        @pack = Kubernetes.new(@integration)
        PublicAddress.stubs(:resolve).returns(IPAddr.new("203.0.113.10"))
        KubernetesApi.any_instance.stubs(:get).raises(KubernetesApi::NotFound, "The API server answered 404: not found")
        KubernetesApi.any_instance.stubs(:list).returns(Pages::Read.new(items: [], complete: true))
        KubernetesApi.any_instance.expects(:patch).never
        KubernetesApi.any_instance.expects(:post).never
      end

      test "a deployment's rollouts are its revisions, the current one ending when Kubernetes marked it complete and an earlier one with no end" do
        stub_get("#{DEPLOYMENTS}/web", deployment)
        stub_list(REPLICA_SETS, replica_sets)

        runs = runs_of(call(:workload_runs, "resource" => "deployment/web"))

        assert_equal %w[4 3 1], runs.map(&:id)
        current, rolled_back, replaced = runs
        assert_equal [ History::SUCCEEDED, nil, Time.utc(2026, 10, 4, 12) ], [ current.status, current.started_at, current.finished_at ]
        assert_match "back to an earlier template, when it began is not kept", current.detail
        assert_equal [ History::CANCELLED, Time.utc(2026, 10, 3, 10), nil ], [ rolled_back.status, rolled_back.started_at, rolled_back.finished_at ]
        assert_match "rolled back by revision 4, images ghcr.io/acme/web:v3", rolled_back.detail
        assert_equal History::SUCCEEDED, replaced.status
        assert_match "replaced by revision 3, Kubernetes keeps no time for when it finished", replaced.detail
        assert_equal "web", current.name
      end

      test "the current rollout fails at its progress deadline, waits while paused, and runs until every pod is updated and available" do
        stub_list(REPLICA_SETS, replica_sets)
        failing = deployment.deep_merge("status" => { "conditions" => [ { "type" => "Progressing", "status" => "False", "reason" => "ProgressDeadlineExceeded",
                                                                           "message" => "ReplicaSet \"web-b\" has timed out progressing.", "lastUpdateTime" => "2026-10-04T12:10:00Z" } ] })
        stub_get("#{DEPLOYMENTS}/web", failing)
        failed = runs_of(call(:workload_runs, "resource" => "web")).first
        assert_equal [ History::FAILED, Time.utc(2026, 10, 4, 12, 10) ], [ failed.status, failed.finished_at ]
        assert_match "has timed out progressing", failed.detail

        stub_get("#{DEPLOYMENTS}/web", deployment.deep_merge("spec" => { "paused" => true }))
        assert_match "paused, waiting for rollout_resume", runs_of(call(:workload_runs, "resource" => "web")).first.detail

        stub_get("#{DEPLOYMENTS}/web", deployment.deep_merge("status" => { "updatedReplicas" => 1, "availableReplicas" => 2 }))
        going = runs_of(call(:workload_runs, "resource" => "web")).first
        assert_equal [ History::RUNNING, nil ], [ going.status, going.finished_at ]
        assert_match "1 of 3 pods updated, 2 available", going.detail
      end

      test "a rollout read by its revision has a part per pod of that revision, a crashing one failed with why and a handle to its own log" do
        stub_get("#{DEPLOYMENTS}/web", deployment)
        stub_list(REPLICA_SETS, replica_sets)
        stub_list(PODS, [ pod("web-b-1", "b", ready: true), pod("web-b-2", "b", crashing: true), pod("web-a-1", "a", ready: true) ])

        text = call(:workload_runs, "resource" => "deployment/web", "run" => "#3")
        run = runs_of(text).sole

        assert_equal "3", run.id
        assert_equal [ "pod web-b-1", "pod web-b-2" ], run.parts.map(&:name)
        ready, crashing = run.parts
        assert_equal [ History::SUCCEEDED, Time.utc(2026, 10, 3, 10, 5) ], [ ready.status, ready.finished_at ]
        assert_equal History::FAILED, crashing.status
        assert_match "web CrashLoopBackOff: back-off 5m0s restarting failed container", crashing.detail
        assert_match "web OOMKilled, exit code 137", crashing.detail
        assert_equal({ "tool" => "workload_logs", "arguments" => { "namespace" => "production", "pod" => "web-b-2", "start" => "2026-10-03T10:00:00Z",
                                                                   "end" => crashing.log.dig("arguments", "end") } }, crashing.log)
        assert_match "kubectl rollout history deployment/web -n production --revision=3", text["content"].first["text"]
        assert_match "has no revision 9", call_error(:workload_runs, "resource" => "web", "run" => "9")
        assert_match "run must be a revision number", call_error(:workload_runs, "resource" => "web", "run" => "latest")
      end

      test "a statefulset's rollout runs until its current revision is the update revision, with no end Kubernetes keeps" do
        statefulset = {
          "metadata" => { "name" => "db", "namespace" => "production", "uid" => "sts-uid", "generation" => 2 },
          "spec" => { "replicas" => 3, "selector" => { "matchLabels" => { "app" => "db" } } },
          "status" => { "observedGeneration" => 2, "currentRevision" => "db-aaa", "updateRevision" => "db-bbb", "updatedReplicas" => 1, "readyReplicas" => 3 }
        }
        stub_get("#{STATEFULSETS}/db", statefulset)
        owner = [ { "controller" => true, "uid" => "sts-uid" } ]
        stub_list(REVISIONS, [
          { "metadata" => { "name" => "db-aaa", "creationTimestamp" => "2026-10-01T10:00:00Z", "ownerReferences" => owner }, "revision" => 1, "data" => {} },
          { "metadata" => { "name" => "db-bbb", "creationTimestamp" => "2026-10-05T10:00:00Z", "ownerReferences" => owner }, "revision" => 2, "data" => {} }
        ])

        going, earlier = runs_of(call(:workload_runs, "resource" => "statefulset/db"))
        assert_equal [ History::RUNNING, Time.utc(2026, 10, 5, 10) ], [ going.status, going.started_at ]
        assert_match "1 of 3 pods updated, 3 ready", going.detail
        assert_equal History::SUCCEEDED, earlier.status

        stub_get("#{STATEFULSETS}/db", statefulset.deep_merge("status" => { "currentRevision" => "db-bbb", "updatedReplicas" => 3 }))
        done = runs_of(call(:workload_runs, "resource" => "statefulset/db")).first
        assert_equal [ History::SUCCEEDED, nil ], [ done.status, done.finished_at ]
        assert_match "Kubernetes keeps no time for when it finished", done.detail
      end

      test "a cronjob's runs are the jobs it controls, each with how it ended, and one read by name has its pods" do
        stub_get("#{CRONJOBS}/nightly", cronjob)
        stub_list(JOBS, [ job("nightly-1", complete: true), job("nightly-2", failed: true), job("nightly-manual-1a2b", manual: true),
                          job("other", owner: "someone-else") ])

        runs = runs_of(call(:workload_runs, "resource" => "cronjob/nightly"))

        assert_equal %w[nightly-manual-1a2b nightly-2 nightly-1], runs.map(&:id)
        manual, failed, complete = runs
        assert_equal [ History::RUNNING, nil ], [ manual.status, manual.finished_at ]
        assert_match "started by hand", manual.detail
        assert_equal [ History::FAILED, Time.utc(2026, 10, 2, 2, 3) ], [ failed.status, failed.finished_at ]
        assert_match "BackoffLimitExceeded: Job has reached the specified backoff limit", failed.detail
        assert_equal [ History::SUCCEEDED, Time.utc(2026, 10, 1, 2, 5), 300 ], [ complete.status, complete.finished_at, complete.seconds ]

        stub_get("#{JOBS}/nightly-2", job("nightly-2", failed: true))
        failing_pod = pod("nightly-2-x", nil, phase: "Failed", terminated: { "reason" => "Error", "exitCode" => 1, "finishedAt" => "2026-10-02T02:02:30Z" })
        stub_list(PODS, [ failing_pod ])
        one = runs_of(call(:workload_runs, "resource" => "nightly", "run" => "nightly-2")).sole
        part = one.parts.sole
        assert_equal [ History::FAILED, Time.utc(2026, 10, 2, 2, 2, 30) ], [ part.status, part.finished_at ]
        assert_match "web Error, exit code 1", part.detail

        stub_get("#{JOBS}/other", job("other", owner: "someone-else"))
        assert_match "has no job called other", call_error(:workload_runs, "resource" => "cronjob/nightly", "run" => "other")
      end

      test "the capability routes run history to workload_runs with the run asked for" do
        route = Capabilities::Kubernetes.route(Capabilities::HISTORY, resource("production/cronjob/nightly", ResourceMap::KIND_JOB), { "run" => "nightly-2", "limit" => 5 })

        assert_equal "workload_runs", route.tool_name
        assert_equal({ "namespace" => "production", "resource" => "cronjob/nightly", "run" => "nightly-2", "limit" => 5 }, route.arguments)
        assert Capabilities::Kubernetes.wraps?("workload_runs")
      end

      test "a deployment pauses and resumes with spec.paused, says when nothing changed, and only a deployment pauses" do
        stub_get("#{DEPLOYMENTS}/web", deployment)
        KubernetesApi.any_instance.expects(:patch).with("#{DEPLOYMENTS}/web", { "spec" => { "paused" => true } }, KubernetesApi::PATCH_MERGE).once

        assert_match "is paused. Its rollout stops where it is", call(:rollout_pause, "resource" => "web")["content"].first["text"]
        assert_match "is already not paused, so nothing changed", call(:rollout_resume, "resource" => "web")["content"].first["text"]

        stub_get("#{STATEFULSETS}/db", { "metadata" => { "name" => "db", "namespace" => "production" }, "spec" => {} })
        assert_match "cannot be paused. Only a deployment's rollout pauses", call_error(:rollout_pause, "resource" => "statefulset/db")
      end

      test "a cronjob runs now as kubectl create job --from does, owned by it and marked as started by hand" do
        stub_get("#{CRONJOBS}/nightly", cronjob)
        posted = nil
        KubernetesApi.any_instance.expects(:post).with { |path, body| path == JOBS && (posted = body) }.once.returns({})

        text = call(:run_cronjob_now, "resource" => "nightly")["content"].first["text"]

        name = posted.dig("metadata", "name")
        assert_match(/\Anightly-manual-\h{8}\z/, name)
        assert_equal({ "cronjob.kubernetes.io/instantiate" => "manual", "team" => "data" }, posted.dig("metadata", "annotations"))
        assert_equal({ "app" => "nightly" }, posted.dig("metadata", "labels"))
        assert_equal [ { "apiVersion" => "batch/v1", "kind" => "CronJob", "name" => "nightly", "uid" => "cj-uid", "controller" => true } ], posted.dig("metadata", "ownerReferences")
        assert_equal cronjob.dig("spec", "jobTemplate", "spec"), posted["spec"]
        assert_match "Started job/#{name} in production from cronjob/nightly in production", text
      end

      test "starting a job the role may not create names the permission" do
        stub_get("#{CRONJOBS}/nightly", cronjob)
        KubernetesApi.any_instance.expects(:post).raises(KubernetesApi::Forbidden, "The API server answered 403: jobs.batch is forbidden")

        assert_match "Give it create on jobs in production", call_error(:run_cronjob_now, "resource" => "cronjob/nightly")
      end

      test "a cronjob suspends and resumes with spec.suspend, saying whether missed runs start at once" do
        stub_get("#{CRONJOBS}/nightly", cronjob.deep_merge("spec" => { "suspend" => true }))
        KubernetesApi.any_instance.expects(:patch).with("#{CRONJOBS}/nightly", { "spec" => { "suspend" => false } }, KubernetesApi::PATCH_MERGE).once

        assert_match "Runs it missed while suspended start at once", call(:resume_cronjob, "resource" => "nightly")["content"].first["text"]
        assert_match "is already suspended, so nothing changed", call(:suspend_cronjob, "resource" => "nightly")["content"].first["text"]
        stub_get("#{DEPLOYMENTS}/web", deployment)
        assert_match "not a cronjob", call_error(:suspend_cronjob, "resource" => "deployment/web")
      end

      private

      def call(tool, arguments = {})
        @pack.call(tool.to_s, environment_row: @row, arguments: arguments)
      end

      def call_error(tool, arguments)
        assert_raises(NativePack::Error) { call(tool, arguments) }.message
      end

      def runs_of(result) = History.runs_of(result)

      def stub_get(path, body) = KubernetesApi.any_instance.stubs(:get).with(path).returns(body)

      def stub_list(path, items)
        KubernetesApi.any_instance.stubs(:list).with { |asked, *| asked == path }.returns(Pages::Read.new(items: items, complete: true))
      end

      def resource(external_id, kind)
        ResourceMap::Resource.new(external_id: external_id, kind: kind, name: external_id.split("/").last)
      end

      def deployment
        {
          "metadata" => { "name" => "web", "namespace" => "production", "uid" => "dep-uid", "generation" => 7, "annotations" => { Kubernetes::REVISION => "4" } },
          "spec" => { "replicas" => 3, "selector" => { "matchLabels" => { "app" => "web" } } },
          "status" => {
            "observedGeneration" => 7, "replicas" => 3, "updatedReplicas" => 3, "readyReplicas" => 3, "availableReplicas" => 3,
            "conditions" => [ { "type" => "Progressing", "status" => "True", "reason" => "NewReplicaSetAvailable", "lastUpdateTime" => "2026-10-04T12:00:00Z" } ]
          }
        }
      end

      # Revision 4 is the replica set first made as revision 2, gone back to after revision 3.
      def replica_sets
        owner = [ { "controller" => true, "uid" => "dep-uid" } ]
        set = lambda do |name, hash, revision, created, image, history = nil|
          { "metadata" => { "name" => name, "creationTimestamp" => created, "ownerReferences" => owner, "labels" => { Kubernetes::POD_TEMPLATE_HASH => hash },
                            "annotations" => { Kubernetes::REVISION => revision, Kubernetes::Runs::REVISION_HISTORY => history }.compact },
            "spec" => { "template" => { "spec" => { "containers" => [ { "name" => "web", "image" => image } ] } } } }
        end
        [ set.call("web-c", "c", "1", "2026-10-01T10:00:00Z", "ghcr.io/acme/web:v1"), set.call("web-a", "a", "4", "2026-10-02T10:00:00Z", "ghcr.io/acme/web:v2", "2"),
          set.call("web-b", "b", "3", "2026-10-03T10:00:00Z", "ghcr.io/acme/web:v3") ]
      end

      def pod(name, hash, ready: false, crashing: false, phase: "Running", terminated: nil)
        status = { "name" => "web", "ready" => ready, "restartCount" => crashing ? 4 : 0 }
        if crashing
          status["state"] = { "waiting" => { "reason" => "CrashLoopBackOff", "message" => "back-off 5m0s restarting failed container" } }
          status["lastState"] = { "terminated" => { "reason" => "OOMKilled", "exitCode" => 137, "finishedAt" => "2026-10-03T10:04:00Z" } }
        end
        status["state"] = { "terminated" => terminated } if terminated
        conditions = ready ? [ { "type" => "Ready", "status" => "True", "lastTransitionTime" => "2026-10-03T10:05:00Z" } ] : []
        { "metadata" => { "name" => name, "creationTimestamp" => "2026-10-03T10:00:00Z", "labels" => { "app" => "web", Kubernetes::POD_TEMPLATE_HASH => hash }.compact },
          "status" => { "phase" => phase, "startTime" => "2026-10-03T10:00:00Z", "conditions" => conditions, "containerStatuses" => [ status ] } }
      end

      def cronjob
        {
          "metadata" => { "name" => "nightly", "namespace" => "production", "uid" => "cj-uid" },
          "spec" => { "schedule" => "0 2 * * *", "jobTemplate" => {
            "metadata" => { "labels" => { "app" => "nightly" }, "annotations" => { "team" => "data" } },
            "spec" => { "backoffLimit" => 2, "template" => { "spec" => { "restartPolicy" => "Never", "containers" => [ { "name" => "nightly", "image" => "acme/nightly:1" } ] } } }
          } }
        }
      end

      def job(name, complete: false, failed: false, manual: false, owner: "cj-uid")
        day = { "nightly-1" => 1, "nightly-2" => 2, "nightly-manual-1a2b" => 3 }.fetch(name, 4)
        started = "2026-10-0#{day}T02:00:00Z"
        conditions = []
        conditions << { "type" => "Complete", "status" => "True" } if complete
        conditions << { "type" => "Failed", "status" => "True", "reason" => "BackoffLimitExceeded", "message" => "Job has reached the specified backoff limit",
                        "lastTransitionTime" => "2026-10-02T02:03:00Z" } if failed
        {
          "metadata" => { "name" => name, "creationTimestamp" => started, "ownerReferences" => [ { "controller" => true, "uid" => owner, "kind" => "CronJob" } ],
                          "annotations" => (manual ? { "cronjob.kubernetes.io/instantiate" => "manual" } : {}) },
          "spec" => { "selector" => { "matchLabels" => { "batch.kubernetes.io/controller-uid" => "#{name}-uid" } } },
          "status" => { "startTime" => started, "completionTime" => ("2026-10-01T02:05:00Z" if complete), "conditions" => conditions,
                        "succeeded" => (1 if complete), "failed" => (3 if failed), "active" => (1 if manual) }.compact
        }
      end
    end
  end
end
