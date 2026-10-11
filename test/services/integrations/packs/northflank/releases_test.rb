require "test_helper"

module Integrations
  module Packs
    class Northflank
      class ReleasesTest < ActiveSupport::TestCase
        History = Capabilities::History

        setup do
          @workspace = workspaces(:slack_workspace_one)
          @integration = Integration.create!(workspace: @workspace, kind: Integration::KIND_NATIVE, provider: "northflank", name: "Northflank")
          @row = @integration.integration_environments.create!
          Northflank.store_credentials!(@row, Northflank::API_TOKEN => "nf-token")
          @row.store_fields!(Northflank::PROJECT => "firefight")
          @pack = Northflank.new(@integration)
          NorthflankApi.any_instance.stubs(:services).returns(listed([
            { "id" => "web", "name" => "web", "serviceType" => "deployment", "appId" => "/firefight-labs/firefight/web" },
            { "id" => "builder", "name" => "builder", "serviceType" => "build", "appId" => "/firefight-labs/firefight/builder" }
          ]))
          NorthflankApi.any_instance.stubs(:addons).returns(listed([]))
          NorthflankApi.any_instance.stubs(:jobs).returns(listed([ { "id" => "migrate", "name" => "migrate", "jobType" => "manual" } ]))
          NorthflankApi.any_instance.stubs(:secret_groups).returns(listed([]))
          NorthflankApi.any_instance.stubs(:workflows).returns(listed([ { "id" => "release", "name" => "Release" } ]))
          NorthflankApi.any_instance.stubs(:pipelines).returns(listed([ { "id" => "shop", "name" => "shop" } ]))
          NorthflankApi.any_instance.stubs(:templates).returns(listed([]))
        end

        test "a workflow's runs are its run history, named by the workflow, each status in Firefight's words" do
          NorthflankApi.any_instance.stubs(:workflow_runs).with("firefight", "release", limit: 20).returns([
            { "id" => "r3", "status" => "approval_wait", "concluded" => false, "startedAt" => "2026-10-11T10:00:00.000Z", "name" => "v1.4" },
            { "id" => "r2", "status" => "success", "concluded" => true, "startedAt" => "2026-10-10T10:00:00.000Z", "concludedAt" => "2026-10-10T10:18:00.000Z" },
            { "id" => "r1", "status" => "failure", "concluded" => true, "startedAt" => "2026-10-09T10:00:00.000Z", "concludedAt" => "2026-10-09T10:04:00.000Z" },
            { "id" => "r0", "status" => "aborted", "concluded" => true, "createdAt" => "2026-10-08T10:00:00.000Z", "concludedAt" => "2026-10-08T10:01:00.000Z" }
          ])

          result = @pack.call("workflow_runs", environment_row: @row, arguments: { "workflow" => "Release" })
          runs = History.runs_of(result)

          assert_equal %w[running succeeded failed cancelled], runs.map(&:status)
          assert_equal [ "Release" ], runs.map(&:name).uniq
          assert_equal "v1.4, waiting for an approval", runs.first.detail
          assert_nil runs.first.finished_at
          assert_equal 18 * 60, result.dig(Telemetry::STRUCTURED, History::USUAL_SECONDS)
          assert_match "recent runs of workflow Release", result["content"].sole["text"]
        end

        test "one run is read with each node as a part: how it went, its error, its retries and where its log is" do
          NorthflankApi.any_instance.stubs(:workflow_run).with("firefight", "release", "r9").returns(run_details)

          run = History.runs_of(@pack.call("workflow_runs", environment_row: @row, arguments: { "workflow" => "release", "run" => "r9" })).sole
          parts = run.parts.index_by(&:name)

          assert_equal [ "Build builder", "Run job migrate", "Release web", "Approval", "Build (build-later)" ], run.parts.map(&:name)
          assert_equal "succeeded", parts["Build builder"].status
          assert_equal({ "tool" => "build_logs", "arguments" => { "resource" => "builder", "build" => "brave-otter-12",
                                                                  "start" => "2026-10-01T10:00:00Z", "end" => "2026-10-01T10:06:00Z" } }, parts["Build builder"].log)
          assert_equal "failed", parts["Run job migrate"].status
          assert_equal "Migration exited with code 1, attempt 3 of 3", parts["Run job migrate"].detail
          assert_equal({ "resource" => "migrate", "run" => "run-77", "start" => "2026-10-01T10:06:00Z", "end" => "2026-10-01T10:09:00Z" },
                       parts["Run job migrate"].log["arguments"])
          assert_equal "search_logs", parts["Release web"].log["tool"]
          assert_equal "web", parts["Release web"].log.dig("arguments", "resource")
          assert_equal [ "queued", nil ], [ parts["Approval"].status, parts["Approval"].log ]
          assert_nil parts["Build (build-later)"].log, "a target not yet resolved has no log to read"
          assert_equal "Run job migrate", run.first_failed_part.name
        end

        test "a release flow's runs are read by its pipeline and stage, and a stage with none says so" do
          NorthflankApi.any_instance.stubs(:release_flow_runs).with("firefight", "shop", "production", limit: 20)
                       .returns([ { "id" => "f1", "status" => "running", "concluded" => false, "startedAt" => "2026-10-11T10:00:00.000Z" } ])
          NorthflankApi.any_instance.stubs(:release_flow_runs).with("firefight", "shop", "staging", limit: 20).raises(NorthflankApi::NotFound, "Northflank answered 404")
          NorthflankApi.any_instance.stubs(:release_flow_run).with("firefight", "shop", "production", "f1").returns(run_details.merge("id" => "f1"))

          listed = History.runs_of(@pack.call("release_flow_runs", environment_row: @row, arguments: { "pipeline" => "shop", "stage" => "production" }))
          one = History.runs_of(@pack.call("release_flow_runs", environment_row: @row, arguments: { "pipeline" => "shop", "stage" => "Production", "run" => "f1" })).sole

          assert_equal [ [ "f1", "shop Production", "running" ] ], listed.map { |run| [ run.id, run.name, run.status ] }
          assert_equal 5, one.parts.size
          error = assert_raises(NativePack::Error) { @pack.call("release_flow_runs", environment_row: @row, arguments: { "pipeline" => "shop", "stage" => "Staging" }) }
          assert_match "shop has no release flow for Staging", error.message
          assert_match "stage must be one of", assert_raises(NativePack::Error) { @pack.call("release_flow_runs", environment_row: @row, arguments: { "pipeline" => "shop", "stage" => "qa" }) }.message
          assert_match "No pipeline called gone", assert_raises(NativePack::Error) { @pack.call("release_flow_runs", environment_row: @row, arguments: { "pipeline" => "gone", "stage" => "Production" }) }.message
        end

        test "workflows, pipelines and each stage's release flow go on the map, linked to what they release" do
          NorthflankApi.any_instance.stubs(:service).returns({})
          NorthflankApi.any_instance.stubs(:workflow).with("firefight", "release").returns("spec" => run_details["spec"])
          NorthflankApi.any_instance.stubs(:pipeline).with("firefight", "shop").returns(
            "name" => "shop", "nfObjects" => [ { "id" => "web", "type" => "service", "stage" => "Production" }, { "id" => "migrate", "type" => "job", "stage" => "Staging" } ]
          )
          NorthflankApi.any_instance.stubs(:release_flow).with("firefight", "shop", "production").returns("spec" => {})
          NorthflankApi.any_instance.stubs(:release_flow).with("firefight", "shop", "staging").raises(NorthflankApi::NotFound, "Northflank answered 404")

          snapshot = @pack.map_of(@row)
          found = snapshot.resources.index_by { |resource| [ resource.kind, resource.external_id ] }
          links = snapshot.links.map { |link| [ link.from.last(2), link.relation, link.to.last(2) ] }

          assert_equal "Release", found.fetch([ ResourceMap::KIND_WORKFLOW, "release" ]).name
          assert_equal "shop", found.fetch([ ResourceMap::KIND_PIPELINE, "shop" ]).name
          assert_equal "shop Production", found.fetch([ ResourceMap::KIND_RELEASE_FLOW, "shop/production" ]).name
          assert_not found.key?([ ResourceMap::KIND_RELEASE_FLOW, "shop/staging" ]), "a stage with no release flow has none on the map"
          assert_includes links, [ [ ResourceMap::KIND_RELEASE_FLOW, "shop/production" ], ResourceMap::RELATION_PART_OF, [ ResourceMap::KIND_PIPELINE, "shop" ] ]
          assert_includes links, [ [ ResourceMap::KIND_SERVICE, "web" ], ResourceMap::RELATION_RELEASED_BY, [ ResourceMap::KIND_RELEASE_FLOW, "shop/production" ] ]
          assert_includes links, [ [ ResourceMap::KIND_BUILD_SERVICE, "builder" ], ResourceMap::RELATION_RELEASED_BY, [ ResourceMap::KIND_WORKFLOW, "release" ] ]
          assert_includes links, [ [ ResourceMap::KIND_JOB, "migrate" ], ResourceMap::RELATION_RELEASED_BY, [ ResourceMap::KIND_WORKFLOW, "release" ] ]
          assert_includes links, [ [ ResourceMap::KIND_SERVICE, "web" ], ResourceMap::RELATION_RELEASED_BY, [ ResourceMap::KIND_WORKFLOW, "release" ] ]
          assert snapshot.complete?
        end

        test "a token that may not read workflows or pipelines leaves a gap naming the permission, and the rest of the map stands" do
          NorthflankApi.any_instance.stubs(:service).returns({})
          NorthflankApi.any_instance.stubs(:workflows).raises(NorthflankApi::Forbidden, "Northflank answered 403: Forbidden")
          NorthflankApi.any_instance.stubs(:pipelines).raises(NorthflankApi::Forbidden, "Northflank answered 403: Forbidden")

          snapshot = @pack.map_of(@row)

          assert snapshot.resources.any? { |resource| resource.external_id == "web" }
          assert_equal [ [ ResourceMap::KIND_WORKFLOW ], [ ResourceMap::KIND_PIPELINE, ResourceMap::KIND_RELEASE_FLOW ] ], snapshot.gaps.map(&:kinds)
          assert_match "Project, Workflows, General, Read", snapshot.gaps.first.text
          assert_match "Project, Pipelines, General, Read", snapshot.gaps.last.text
        end

        test "a release notification re-reads that pipeline's release flows, or every one when it named none, and a pipeline gone is gone" do
          place!(ResourceMap::KIND_SERVICE, "web")
          NorthflankApi.any_instance.stubs(:pipeline).with("firefight", "shop").returns("name" => "shop", "nfObjects" => [ { "id" => "web", "type" => "service", "stage" => "Production" } ])
          NorthflankApi.any_instance.stubs(:release_flow).returns("spec" => {})
          NorthflankApi.any_instance.expects(:services).never

          one = @pack.map_refresh(@row, ResourceMap::Scope.new(kind: ResourceMap::KIND_RELEASE_FLOW, external_id: "shop/production"))
          every = @pack.map_refresh(@row, ResourceMap::Scope.new(kind: ResourceMap::KIND_RELEASE_FLOW))

          assert_equal [ "shop", "shop/production" ], one.resources.map(&:external_id).sort
          assert_includes one.links.map { |link| [ link.from.last, link.to.last ] }, [ "web", "shop/production" ]
          assert_equal one.resources.map(&:key).sort, every.resources.map(&:key).sort
          assert_empty every.gone

          NorthflankApi.any_instance.stubs(:pipeline).with("firefight", "shop").raises(NorthflankApi::NotFound, "Northflank answered 404")
          gone = @pack.map_refresh(@row, ResourceMap::Scope.new(kind: ResourceMap::KIND_PIPELINE, external_id: "shop"))
          assert_includes gone.gone, [ "northflank", "firefight-labs/firefight", ResourceMap::KIND_PIPELINE, "shop" ]
          assert_includes gone.gone, [ "northflank", "firefight-labs/firefight", ResourceMap::KIND_RELEASE_FLOW, "shop/production" ]
        end

        private

        def listed(items) = Pages::Read.new(items: items, complete: true)

        def place!(kind, id)
          ResourceMap::Resource.create!(workspace: @workspace, provider: "northflank", account: "firefight-labs/firefight", kind: kind, external_id: id,
                                        name: id, integration_environment: @row, first_seen_at: Time.current, last_seen_at: Time.current)
        end

        # A sequential workflow as get-workflow-run-details answers it, a node of each kind a release uses.
        def run_details
          ten = Time.utc(2026, 10, 1, 10).to_i
          {
            "id" => "r9", "status" => "failure", "concluded" => true, "startedAt" => "2026-10-11T10:00:00.000Z", "concludedAt" => "2026-10-11T10:09:00.000Z",
            "spec" => {
              "kind" => "Workflow", "response" => { "status" => "failure" },
              "spec" => {
                "type" => "sequential",
                "steps" => [
                  { "kind" => "Build", "ref" => "build-1", "spec" => { "id" => "builder", "type" => "service" },
                    "response" => { "status" => "success", "startTime" => ten, "endTime" => ten + 360, "data" => { "id" => "brave-otter-12", "nfObjectId" => "builder" } } },
                  { "kind" => "JobRun", "ref" => "migrate-1", "spec" => { "jobId" => "migrate" },
                    "response" => { "status" => "failure", "startTime" => ten + 360, "endTime" => ten + 540, "data" => { "id" => "run-77" },
                                    "error" => { "code" => 1, "message" => "Migration exited with code 1" },
                                    "retries" => { "attempts" => 3, "maxAttempts" => 3, "timestamp" => ten + 500 } } },
                  { "kind" => "Workflow", "spec" => { "type" => "parallel", "steps" => [
                    { "kind" => "Release", "ref" => "release-web", "spec" => { "target" => { "id" => "web", "type" => "service" } }, "response" => { "status" => "aborted" } },
                    { "kind" => "Approval", "ref" => "approve", "spec" => {} }
                  ] } },
                  { "kind" => "Build", "ref" => "build-later", "spec" => { "id" => "${refs.builder.id}", "type" => "service" }, "response" => { "status" => "skipped" } }
                ]
              }
            }
          }
        end
      end
    end
  end
end
