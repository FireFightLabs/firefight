require "test_helper"

module Integrations
  module Packs
    class Northflank
      # The team's templates, read from the shapes Northflank's API reference documents for List templates, List template
      # runs, Get template run, Run template and Abort template run.
      class TemplatesTest < ActiveSupport::TestCase
        History = Capabilities::History

        setup do
          Http.stubs(:request).raises(RuntimeError, "a test reached for the network")
          @workspace = workspaces(:slack_workspace_one)
          @integration = Integration.create!(workspace: @workspace, kind: Integration::KIND_NATIVE, provider: "northflank", name: "Northflank")
          @row = @integration.integration_environments.create!
          Northflank.store_credentials!(@row, Northflank::API_TOKEN => "nf-token")
          @row.store_fields!(Northflank::PROJECT => "firefight")
          @pack = Northflank.new(@integration)
          NorthflankApi.any_instance.stubs(:templates).returns(listed([
            { "id" => "preview-stack", "name" => "Preview stack", "apiVersion" => "v1.2" },
            { "id" => "nightly", "name" => "Nightly", "apiVersion" => "v1.2" }
          ]))
        end

        test "a template's runs are its run history, named by the template, each status in Firefight's words, linked to the Templates page" do
          NorthflankApi.any_instance.stubs(:template_runs).with("preview-stack", limit: 20).returns([
            { "id" => "t3", "templateId" => "preview-stack", "name" => "Preview stack", "status" => "approval_wait", "concluded" => false,
              "startedAt" => "2026-10-11T10:00:00.000Z", "createdAt" => "2026-10-11T10:00:00.000Z", "updatedAt" => "2026-10-11T10:01:00.000Z" },
            { "id" => "t2", "templateId" => "preview-stack", "name" => "Preview stack", "status" => "success", "concluded" => true,
              "startedAt" => "2026-10-10T10:00:00.000Z", "concludedAt" => "2026-10-10T10:12:00.000Z", "createdAt" => "2026-10-10T10:00:00.000Z", "updatedAt" => "2026-10-10T10:12:00.000Z" },
            { "id" => "t1", "templateId" => "preview-stack", "name" => "Preview stack", "status" => "aborted", "concluded" => true,
              "createdAt" => "2026-10-09T10:00:00.000Z", "concludedAt" => "2026-10-09T10:02:00.000Z", "updatedAt" => "2026-10-09T10:02:00.000Z" }
          ])

          result = @pack.call("template_runs", environment_row: @row, arguments: { "template" => "preview stack" })
          runs = History.runs_of(result)

          assert_equal %w[running succeeded cancelled], runs.map(&:status)
          assert_equal [ "Preview stack" ], runs.map(&:name).uniq
          assert_equal "waiting for an approval", runs.first.detail, "the run's own name is the template's, so it is not repeated"
          assert_equal 12 * 60, result.dig(Telemetry::STRUCTURED, History::USUAL_SECONDS)
          assert_match "recent runs of template Preview stack", result["content"].sole["text"]
          assert_includes result["content"].sole["text"], "https://app.northflank.com/s/account/templates"
        end

        test "once the map holds the team, a template's runs link to their page and each run, a run started or aborted too" do
          ResourceMap::Resource.create!(workspace: @workspace, provider: "northflank", account: "firefight-labs", kind: ResourceMap::KIND_STACK,
                                        external_id: "preview-stack", name: "Preview stack", integration_environment: @row,
                                        first_seen_at: Time.current, last_seen_at: Time.current)
          NorthflankApi.any_instance.stubs(:template_runs).with("preview-stack", limit: 20).returns([
            { "id" => "t3", "status" => "running", "concluded" => false, "startedAt" => "2026-10-11T10:00:00.000Z", "createdAt" => "2026-10-11T10:00:00.000Z" }
          ])
          NorthflankApi.any_instance.stubs(:run_template).returns("id" => "t4", "status" => "pending")
          NorthflankApi.any_instance.stubs(:abort_template_run).returns("id" => "t3", "status" => "aborting")
          NorthflankApi.any_instance.expects(:services).never
          page = "https://app.northflank.com/t/firefight-labs/templates/preview-stack/runs"

          result = @pack.call("template_runs", environment_row: @row, arguments: { "template" => "preview-stack" })

          assert_equal "#{page}/t3", History.runs_of(result).sole.url
          assert_match %r{#{page}\z}, result["content"].sole["text"].lines.last
          assert_match %r{#{page}/t4\z}, @pack.call("run_template", environment_row: @row, arguments: { "template" => "preview-stack" })["content"].sole["text"]
          assert_match %r{#{page}/t3\z}, @pack.call("abort_template_run", environment_row: @row, arguments: { "template" => "preview-stack", "run" => "t3" })["content"].sole["text"]
        end

        test "a map that holds only a project, with no team named, links a template's runs to the Templates page" do
          ResourceMap::Resource.create!(workspace: @workspace, provider: "northflank", account: "firefight", kind: ResourceMap::KIND_JOB,
                                        external_id: "nightly", name: "nightly", integration_environment: @row,
                                        first_seen_at: Time.current, last_seen_at: Time.current)
          NorthflankApi.any_instance.stubs(:template_runs).returns([])

          text = @pack.call("template_runs", environment_row: @row, arguments: { "template" => "preview-stack" })["content"].sole["text"]

          assert_match %r{app\.northflank\.com/s/account/templates\z}, text
        end

        test "one run is read with each node as a part, its log read only in a project this connection reaches" do
          NorthflankApi.any_instance.stubs(:template_run).with("preview-stack", "t9").returns(run_details)

          run = History.runs_of(@pack.call("template_runs", environment_row: @row, arguments: { "template" => "preview-stack", "run" => "t9" })).sole
          parts = run.parts.index_by(&:name)

          assert_equal [ "Project firefight", "Build builder", "Release web", "Build api", "Release worker" ], run.parts.map(&:name)
          assert_equal({ "tool" => "build_logs", "arguments" => { "resource" => "builder", "build" => "brave-otter-12", "start" => "2026-10-01T10:00:00Z",
                                                                  "end" => "2026-10-01T10:05:00Z", "project" => "firefight" } }, parts["Build builder"].log)
          assert_equal "firefight", parts["Release web"].log.dig("arguments", "project"), "a project made in the run is read from its refs"
          assert_nil parts["Build api"].log, "a node in a project this connection does not reach has no log here"
          assert_nil parts["Release worker"].log, "a node whose project is not known yet has no log"
          assert_equal "failed", parts["Release web"].status
          assert_equal "Service web did not become healthy", parts["Release web"].detail
          assert_equal "Release web", run.first_failed_part.name
        end

        test "a template that is not there names the team's templates, and a token that may not read them says the permission" do
          error = assert_raises(NativePack::Error) { @pack.call("template_runs", environment_row: @row, arguments: { "template" => "gone" }) }
          assert_equal "No template called gone in the team. Its templates are Preview stack and Nightly.", error.message

          NorthflankApi.any_instance.stubs(:templates).raises(NorthflankApi::Forbidden, "Northflank answered 403: Forbidden")
          error = assert_raises(NativePack::Error) { @pack.call("template_runs", environment_row: @row, arguments: { "template" => "nightly" }) }
          assert_match "Account, Templates, General, Read", error.message
        end

        test "run_template starts a run with its arguments and refuses arguments that hold a secret or are not an object" do
          NorthflankApi.any_instance.expects(:run_template).with("nightly", { "version" => "v1.4" })
                       .returns("id" => "t10", "templateId" => "nightly", "status" => "pending", "concluded" => false)

          result = @pack.call("run_template", environment_row: @row, arguments: { "template" => "Nightly", "arguments" => { "version" => "v1.4" } })

          assert_match "Started run t10 of template Nightly, now pending.", result["content"].sole["text"]
          assert_raises(PolicyRefusal) do
            @pack.call("run_template", environment_row: @row, arguments: { "template" => "nightly", "arguments" => { "token" => "ghp_#{'a' * 36}" } })
          end
          assert_match "arguments must be an object", assert_raises(NativePack::Error) {
            @pack.call("run_template", environment_row: @row, arguments: { "template" => "nightly", "arguments" => "v1.4" })
          }.message
        end

        test "a token that may not run or abort templates is told the permission to give" do
          NorthflankApi.any_instance.stubs(:run_template).raises(NorthflankApi::Forbidden, "Northflank answered 403: Forbidden")
          NorthflankApi.any_instance.stubs(:abort_template_run).raises(NorthflankApi::Forbidden, "Northflank answered 403: Forbidden")

          assert_match "Account, Templates, General, Run", assert_raises(NativePack::Error) { @pack.call("run_template", environment_row: @row, arguments: { "template" => "nightly" }) }.message
          assert_match "Account, Templates, Runs, Abort", assert_raises(NativePack::Error) {
            @pack.call("abort_template_run", environment_row: @row, arguments: { "template" => "nightly", "run" => "t10" })
          }.message
        end

        test "abort_template_run aborts the run named" do
          NorthflankApi.any_instance.expects(:abort_template_run).with("nightly", "t10").returns("id" => "t10", "status" => "aborting", "concluded" => false)

          result = @pack.call("abort_template_run", environment_row: @row, arguments: { "template" => "nightly", "run" => "#t10" })

          assert_match "Asked Northflank to abort run t10 of template Nightly, now aborting.", result["content"].sole["text"]
          assert_match "run must be the run's id", assert_raises(NativePack::Error) {
            @pack.call("abort_template_run", environment_row: @row, arguments: { "template" => "nightly", "run" => "../x" })
          }.message
        end

        test "the client reads and changes templates under /v1/templates, the token's own team, never a project" do
          Http.expects(:json).with { |uri, request, **| uri.to_s == "https://api.northflank.com/v1/templates/nightly/runs?per_page=5" && request.is_a?(Net::HTTP::Get) }
              .returns("data" => { "templateRuns" => [ { "id" => "t1" } ] })
          Http.expects(:json).with { |uri, request, **| uri.path == "/v1/templates/nightly/runs/t1" && request.is_a?(Net::HTTP::Get) }.returns("data" => { "id" => "t1" })
          Http.expects(:json).with { |uri, request, **| uri.path == "/v1/templates/nightly/runs" && request.is_a?(Net::HTTP::Post) && JSON.parse(request.body) == { "arguments" => { "a" => "b" } } }
              .returns("data" => { "id" => "t2" })
          Http.expects(:json).with { |uri, request, **| uri.path == "/v1/templates/nightly/runs/t2/abort" && request.is_a?(Net::HTTP::Post) }.returns("data" => { "id" => "t2" })
          api = NorthflankApi.new("nf-token")

          assert_equal [ { "id" => "t1" } ], api.template_runs("nightly", limit: 5)
          assert_equal "t1", api.template_run("nightly", "t1")["id"]
          assert_equal "t2", api.run_template("nightly", { "a" => "b" })["id"]
          assert_equal "t2", api.abort_template_run("nightly", "t2")["id"]
        end

        test "the team's templates go on the map once, as stacks under the team, whichever projects the connection reaches" do
          stub_project_reads
          NorthflankApi.any_instance.expects(:templates).once.returns(listed([ { "id" => "preview-stack", "name" => "Preview stack", "description" => "A preview" } ]))

          snapshot = @pack.map_of(@row)
          stack = snapshot.resources.find { |found| found.kind == ResourceMap::KIND_STACK }

          assert_equal [ "northflank", "firefight-labs", ResourceMap::KIND_STACK, "preview-stack" ], stack.key
          assert_equal "Preview stack", stack.name
          assert_equal({ "type" => "template", "description" => "A preview" }, stack.details)
          assert_nil stack.url, "Northflank documents no page of a template's own"
          assert snapshot.complete?
        end

        test "a token that may not read templates leaves words in the gaps and takes nothing off the map, and another error keeps the stacks" do
          stub_project_reads
          NorthflankApi.any_instance.stubs(:templates).raises(NorthflankApi::Forbidden, "Northflank answered 403: Forbidden")

          refused = @pack.map_of(@row)
          assert refused.complete?
          assert_match "Account, Templates, General, Read", refused.gap_texts.sole

          NorthflankApi.any_instance.stubs(:templates).raises(NorthflankApi::Error, "Northflank answered 500")
          failed = @pack.map_of(@row)
          assert_equal [ ResourceMap::KIND_STACK ], failed.unread_kinds
        end

        test "a connection whose projects hold no service yet says why its templates are not on the map, and reads none" do
          stub_project_reads
          NorthflankApi.any_instance.stubs(:services).returns(listed([]))
          NorthflankApi.any_instance.expects(:templates).never

          snapshot = @pack.map_of(@row)

          assert snapshot.complete?
          assert_equal [ Templates::NO_TEAM ], snapshot.gap_texts
        end

        test "run history on a template on the map reads its runs, and the two changes are changes, aborting one stopping what someone started" do
          Integrations::DiscoveryService.sync!(@integration)
          stack = ResourceMap::Resource.create!(workspace: @workspace, provider: "northflank", account: "firefight-labs", kind: ResourceMap::KIND_STACK,
                                                external_id: "nightly", name: "Nightly", integration_environment: @row, first_seen_at: Time.current, last_seen_at: Time.current)
          route = Capabilities::Northflank.route(Capabilities::HISTORY, stack, { "run" => "t1" })
          tools = @integration.tools.index_by(&:name)

          assert_equal [ "template_runs", { "template" => "nightly", "run" => "t1" } ], [ route.tool_name, route.arguments ]
          assert tools.fetch("template_runs").read_only
          assert_not tools.fetch("run_template").read_only
          assert_not tools.fetch("abort_template_run").read_only
          assert tools.fetch("abort_template_run").ability_action.effect?(Ability::Action::EFFECT_STOPS)
          assert_not tools.fetch("run_template").ability_action.effect?(Ability::Action::EFFECT_STOPS)
        end

        test "a member reads template runs without a grant, and starting or aborting one needs a grant" do
          Integrations::DiscoveryService.sync!(@integration)
          member = workspace_memberships(:bob_workspace_one)
          tools = @integration.tools.index_by(&:name)

          assert AbilityGateway.authorize!(principal: member, action_key: tools.fetch("template_runs").action_key, workspace: @workspace) { true }
          [ "run_template", "abort_template_run" ].each do |name|
            assert_raises(AbilityGateway::Denied) { AbilityGateway.authorize!(principal: member, action_key: tools.fetch(name).action_key, workspace: @workspace) { true } }
          end
        end

        private

        def listed(items) = Pages::Read.new(items: items, complete: true)

        def stub_project_reads
          NorthflankApi.any_instance.stubs(:services).returns(listed([ { "id" => "web", "name" => "web", "serviceType" => "deployment", "appId" => "/firefight-labs/firefight/web" } ]))
          NorthflankApi.any_instance.stubs(:service).returns({})
          NorthflankApi.any_instance.stubs(:addons).returns(listed([]))
          NorthflankApi.any_instance.stubs(:jobs).returns(listed([]))
          NorthflankApi.any_instance.stubs(:secret_groups).returns(listed([]))
          NorthflankApi.any_instance.stubs(:workflows).returns(listed([]))
          NorthflankApi.any_instance.stubs(:pipelines).returns(listed([]))
        end

        # A template run as Get template run answers it: a sequential workflow that makes a project, then works in it
        # through a workflow whose context names the project by its ref, and in another project the connection does not
        # reach.
        def run_details
          ten = Time.utc(2026, 10, 1, 10).to_i
          {
            "id" => "t9", "templateId" => "preview-stack", "name" => "Preview stack", "status" => "failure", "concluded" => true,
            "createdAt" => "2026-10-01T10:00:00.000Z", "updatedAt" => "2026-10-01T10:09:00.000Z",
            "refs" => { "project" => { "id" => "firefight" } },
            "spec" => {
              "kind" => "Workflow", "response" => { "status" => "failure" },
              "spec" => {
                "type" => "sequential",
                "steps" => [
                  { "kind" => "Project", "ref" => "project", "spec" => { "name" => "firefight" }, "response" => { "status" => "success", "startTime" => ten - 60, "endTime" => ten } },
                  { "kind" => "Workflow", "spec" => { "type" => "sequential", "context" => { "projectId" => "${refs.project.id}" }, "steps" => [
                    { "kind" => "Build", "ref" => "build", "spec" => { "id" => "builder", "type" => "service" },
                      "response" => { "status" => "success", "startTime" => ten, "endTime" => ten + 300, "data" => { "id" => "brave-otter-12", "nfObjectId" => "builder" } } },
                    { "kind" => "Release", "ref" => "release", "spec" => { "target" => { "id" => "web", "type" => "service" } },
                      "response" => { "status" => "failure", "startTime" => ten + 300, "endTime" => ten + 540, "error" => { "message" => "Service web did not become healthy" } } }
                  ] } },
                  { "kind" => "Build", "ref" => "other", "spec" => { "id" => "api", "type" => "service", "projectId" => "billing" },
                    "response" => { "status" => "success", "startTime" => ten, "endTime" => ten + 200, "data" => { "id" => "calm-fox-3", "nfObjectId" => "api" } } },
                  { "kind" => "Release", "ref" => "later", "spec" => { "target" => { "id" => "worker", "type" => "service" } }, "response" => { "status" => "skipped" } }
                ]
              }
            }
          }
        end
      end
    end
  end
end
