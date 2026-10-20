require "test_helper"

module Integrations
  module Packs
    class VercelTest < ActiveSupport::TestCase
      PROJECT_PAGE = "https://vercel.com/acme/shop".freeze

      setup do
        @workspace = workspaces(:slack_workspace_one)
        @integration = Integration.create!(workspace: @workspace, kind: Integration::KIND_NATIVE, provider: "vercel", name: "Vercel")
        @row = @integration.integration_environments.create!
        Vercel.store_credentials!(@row, Vercel::API_TOKEN => " tok ")
        @row.store_fields!(Vercel::TEAM => "acme")
        @pack = Vercel.new(@integration)
        VercelApi.any_instance.stubs(:projects).returns(Integrations::Pages::Read.new(items: [
          { "id" => "prj_1", "name" => "shop", "accountId" => "team_1", "framework" => "nextjs",
            "link" => { "type" => "github", "org" => "acme", "repo" => "shop", "productionBranch" => "main" },
            "targets" => { "production" => { "id" => "dpl_2", "readyState" => "READY", "meta" => { "githubCommitSha" => "c4e4267d46e638ac" } } } }
        ], complete: true))
        VercelApi.any_instance.stubs(:project_env).returns([ [], false ])
      end

      test "the token and team are stored trimmed, and only the deployment and rolling release changes change anything" do
        assert_equal "tok", ConnectionSettings.of(@row.reload).credential(Vercel::API_TOKEN)
        assert_equal %w[rollback_deployment promote_deployment cancel_deployment redeploy_deployment advance_rolling_release complete_rolling_release abort_rolling_release],
                     Vercel.tool_definitions.reject(&:read_only).map(&:name)
      end

      test "a wrong token or team is said on the form before anything is saved" do
        VercelApi.any_instance.stubs(:check!).raises(VercelApi::Error, "Vercel answered 403: Not authorized")

        assert_equal "Paste an access token.", Vercel.credential_refusal({}, fields: { Vercel::TEAM => "acme" })
        assert_equal "Vercel refused this token or team: Vercel answered 403: Not authorized.", Vercel.credential_refusal({ Vercel::API_TOKEN => "x" })
        assert IntegrationProvider.find(Vercel::PROVIDER_KEY).connect_fields.sole.optional, "the team may be left empty for a personal account"
      end

      test "projects are listed with their production state" do
        assert_match "shop (prj_1), nextjs, production ready", call(:list_resources)
      end

      test "a project list cut short says so and links the team's page, and a project past it is read by its id or name" do
        VercelApi.any_instance.stubs(:projects).returns(Integrations::Pages::Read.new(items: [ { "id" => "prj_1", "name" => "shop" } ], complete: false))

        result = @pack.call("list_resources", environment_row: @row, arguments: {})

        assert_match "Only the first 1 projects were read.", result["content"].sole["text"]
        assert_match "https://vercel.com/acme", result["content"].sole["text"]

        VercelApi.any_instance.stubs(:project).with("blog").returns("id" => "prj_9", "name" => "blog")
        assert_equal "prj_9", @pack.send(:find_project, @row, "blog")["id"]

        VercelApi.any_instance.stubs(:project).with("nowhere").raises(VercelApi::Error, "Vercel answered 404: not found")
        error = assert_raises(Integrations::Error) { @pack.send(:find_project, @row, "nowhere") }
        assert_equal "No project called nowhere among the first 1 projects read from this team, and Vercel has none by that id or name.", error.message
      end

      test "deployments say which serves production, what failed and their page, and link to the project" do
        VercelApi.any_instance.stubs(:deployments).with("prj_1", limit: 20, target: nil).returns([
          { "uid" => "dpl_3", "target" => "production", "readyState" => "ERROR", "createdAt" => 1_790_000_000_000, "errorCode" => "BUILD_FAILED",
            "errorMessage" => "Command failed", "meta" => { "githubCommitSha" => "aaaabbbbccccdddd", "githubCommitMessage" => "Break it\nmore",
                                                              "githubCommitRef" => "main" }, "creator" => { "username" => "ada" },
            "inspectorUrl" => "https://vercel.com/acme/shop/3" },
          { "uid" => "dpl_2", "target" => "production", "readyState" => "READY", "readySubstate" => "PROMOTED", "createdAt" => 1_789_990_000_000 }
        ])

        text = call(:list_deployments, "resource" => "SHOP")

        assert_match "dpl_3, production, error, aaaabbbbcccc \"Break it\", on main, by ada, failed: BUILD_FAILED: Command failed, page https://vercel.com/acme/shop/3", text
        assert_match "dpl_2, production, ready, promoted, serving production now", text
        assert text.end_with?(PROJECT_PAGE)
      end

      test "deployments carry their commit, branch, state and whether they serve production as data" do
        VercelApi.any_instance.stubs(:deployments).with("prj_1", limit: 20, target: nil).returns([
          { "uid" => "dpl_4", "target" => "production", "readyState" => "BUILDING", "createdAt" => 1_790_000_100_000, "buildingAt" => 1_790_000_105_000,
            "meta" => { "githubCommitSha" => "BBBBCCCCDDDDEEEE", "githubCommitRef" => "main" } },
          { "uid" => "dpl_2", "target" => "production", "readyState" => "READY", "createdAt" => 1_789_990_000_000, "ready" => 1_789_990_060_000,
            "meta" => { "githubCommitSha" => "c4e4267d46e638ac", "githubCommitRef" => "main" } },
          { "uid" => "dpl_1", "target" => "production", "readyState" => "READY", "createdAt" => 1_789_980_000_000, "ready" => 1_789_980_060_000 }
        ])

        deploys = Capabilities::Deploys.deploys_of(@pack.call("list_deployments", environment_row: @row, arguments: { "resource" => "shop" }))

        assert_equal [ [ "dpl_4", "bbbbccccddddeeee", "main", Capabilities::History::RUNNING, false, Time.zone.at(1_790_000_105), nil ],
                       [ "dpl_2", "c4e4267d46e638ac", "main", Capabilities::History::SUCCEEDED, true, Time.zone.at(1_789_990_000), Time.zone.at(1_789_990_060) ],
                       [ "dpl_1", nil, nil, Capabilities::History::SUCCEEDED, false, Time.zone.at(1_789_980_000), Time.zone.at(1_789_980_060) ] ],
                     deploys.map { |deploy| [ deploy.id, deploy.commit, deploy.branch, deploy.status, deploy.live, deploy.started_at, deploy.finished_at ] }
      end

      test "a project's status names the repository, production, the last rollback and its domains" do
        VercelApi.any_instance.stubs(:project).with("prj_1").returns(
          "name" => "shop", "framework" => "nextjs", "link" => { "type" => "github", "org" => "acme", "repo" => "shop", "productionBranch" => "main" },
          "targets" => { "production" => { "id" => "dpl_2", "readyState" => "READY" } },
          "lastAliasRequest" => { "type" => "rollback", "toDeploymentId" => "dpl_2", "fromDeploymentId" => "dpl_3", "jobStatus" => "succeeded" }
        )
        VercelApi.any_instance.stubs(:project_domains).returns(Integrations::Pages::Read.new(items: [ { "name" => "shop.acme.dev", "verified" => true } ], complete: true))

        text = call(:describe_resource, "resource" => "shop")

        assert_match "Git: github acme/shop, production branch main", text
        assert_match "Last rollback: to dpl_2 from dpl_3, succeeded. New deployments do not go live on their own until one is promoted", text
        assert_match "Domains:\nshop.acme.dev", text
      end

      test "build logs read the newest deployment's output and say why it failed" do
        VercelApi.any_instance.stubs(:deployments).with("prj_1", limit: 1).returns([ { "uid" => "dpl_3" } ])
        VercelApi.any_instance.stubs(:deployment).with("dpl_3").returns(
          "id" => "dpl_3", "projectId" => "prj_1", "errorCode" => "BUILD_FAILED", "errorMessage" => "Command \"npm run build\" exited with 1",
          "inspectorUrl" => "https://vercel.com/acme/shop/3"
        )
        VercelApi.any_instance.stubs(:deployment_events).with("dpl_3", limit: 200).returns([
          { "type" => "stderr", "created" => 1_790_000_000_000, "payload" => { "text" => "Module not found: zod", "date" => 1_790_000_000_000 } },
          { "type" => "deployment-state", "created" => 1_790_000_000_000, "payload" => { "text" => "" } }
        ])

        text = call(:deployment_logs, "resource" => "shop", "type" => "build")

        assert text.start_with?("dpl_3 failed: BUILD_FAILED: Command \"npm run build\" exited with 1\n")
        assert_match "stderr Module not found: zod", text
        assert text.end_with?("https://vercel.com/acme/shop/3")
      end

      test "runtime logs are watched live on production, filtered, and say where older lines are" do
        VercelApi.any_instance.stubs(:deployment).with("dpl_2").returns("id" => "dpl_2", "projectId" => "prj_1")
        VercelApi.any_instance.expects(:runtime_logs).with("prj_1", "dpl_2", seconds: 60, limit: 200).returns([
          { "level" => "error", "message" => "FUNCTION_INVOCATION_TIMEOUT", "source" => "serverless", "requestMethod" => "GET",
            "requestPath" => "/api/cart", "responseStatusCode" => 504, "timestampInMs" => 1_790_000_000_000 },
          { "level" => "info", "message" => "ok", "source" => "serverless", "timestampInMs" => 1_790_000_001_000 }
        ])

        text = call(:deployment_logs, "resource" => "shop", "seconds" => 600, "exclude" => "ok")

        assert_match "serverless error GET /api/cart 504 FUNCTION_INVOCATION_TIMEOUT", text
        assert_no_match "info", text
        assert_match "keeps them 1 hour on Hobby", text
        assert text.end_with?("#{PROJECT_PAGE}/logs")
      end

      test "a deployment of another project is refused, a Hobby rollback says what to do, and a preview cannot be promoted" do
        VercelApi.any_instance.stubs(:deployment).with("dpl_9").returns("id" => "dpl_9", "projectId" => "prj_other")
        assert_match "is not a deployment of shop", assert_raises(NativePack::Error) { call(:rollback_deployment, "resource" => "shop", "deployment" => "dpl_9") }.message

        VercelApi.any_instance.stubs(:deployment).with("dpl_1").returns("id" => "dpl_1", "projectId" => "prj_1", "target" => nil)
        VercelApi.any_instance.stubs(:rollback).raises(VercelApi::PlanLimited, "Vercel answered 402: upgrade")
        assert_match "only go to the previous production deployment", assert_raises(NativePack::Error) { call(:rollback_deployment, "resource" => "shop", "deployment" => "dpl_1") }.message

        VercelApi.any_instance.expects(:promote).never
        assert_match "is a preview deployment", assert_raises(NativePack::Error) { call(:promote_deployment, "resource" => "shop", "deployment" => "dpl_1") }.message
      end

      test "a rollback says new deployments stop going live, and a queued promotion says so" do
        VercelApi.any_instance.stubs(:deployment).with("dpl_1").returns("id" => "dpl_1", "projectId" => "prj_1", "target" => "production")
        VercelApi.any_instance.expects(:rollback).with("prj_1", "dpl_1", description: "bad deploy").returns(Integrations::Http::Answer.new(status: 201, body: {}))
        assert_match "New deployments no longer go live on their own", call(:rollback_deployment, "resource" => "shop", "deployment" => "dpl_1", "reason" => "bad deploy")

        VercelApi.any_instance.stubs(:promote).returns(Integrations::Http::Answer.new(status: 202, body: {}))
        assert_match "queued the promotion of dpl_1", call(:promote_deployment, "resource" => "shop", "deployment" => "dpl_1")
      end

      test "projects go on the map with their repository and verified domains, and a team id is turned into its slug for the page" do
        Vercel.store_credentials!(@row, Vercel::API_TOKEN => "tok")
        @row.store_fields!(Vercel::TEAM => "team_1")
        VercelApi.any_instance.stubs(:team).with("team_1").returns("slug" => "acme")
        VercelApi.any_instance.stubs(:project_domains).returns(Integrations::Pages::Read.new(items: [
          { "name" => "shop.acme.dev", "verified" => true }, { "name" => "www.acme.dev", "verified" => true, "redirect" => "shop.acme.dev" },
          { "name" => "new.acme.dev", "verified" => false }
        ], complete: true))

        snapshot = @pack.map_of(@row)

        project = snapshot.resources.find { |found| found.external_id == "prj_1" }
        assert_equal [ ResourceMap::KIND_SITE, "team_1", "ready", PROJECT_PAGE, "c4e4267d46e638ac" ],
                     [ project.kind, project.account, project.status, project.url, project.details[ResourceMap::DEPLOYED_COMMIT] ]
        assert_equal [ [ "prj_1", ResourceMap::RELATION_BUILT_FROM, "acme/shop" ], [ "shop.acme.dev", ResourceMap::RELATION_SERVED_BY, "prj_1" ] ],
                     snapshot.links.map { |link| [ link.from.last, link.relation, link.to.last ] }
      end

      test "a project whose domains cannot be read is a gap, and with no slug known there is no page" do
        Vercel.store_credentials!(@row, Vercel::API_TOKEN => "tok")
        @row.store_fields!({})
        VercelApi.any_instance.stubs(:user).raises(VercelApi::Error, "Vercel answered 403: forbidden")
        VercelApi.any_instance.stubs(:project_domains).raises(VercelApi::Error, "Vercel answered 403: forbidden")

        snapshot = @pack.map_of(@row)

        assert_nil snapshot.resources.find { |found| found.external_id == "prj_1" }.url
        assert_equal [ "The domains of shop could not be read: Vercel answered 403: forbidden." ], snapshot.gaps.map(&:text)
        assert_equal [ ResourceMap::KIND_DOMAIN ], snapshot.unread_kinds, "a domain list Vercel refused takes no domain off the map"
      end

      test "production's plain settings are read by value, every other type by name, and no value is kept" do
        VercelApi.any_instance.stubs(:project_domains).returns(Integrations::Pages::Read.new(items: [], complete: true))
        plain = "postgres://shop:vercel-plain-pw@ep-shop.us-east-2.aws.neon.tech/shop"
        VercelApi.any_instance.stubs(:project_env).with("prj_1").returns([ [
          { "key" => "DATABASE_URL", "type" => "plain", "value" => plain, "target" => [ "production", "preview" ] },
          { "key" => "PREVIEW_DB_URL", "type" => "plain", "value" => "postgres://u:p@preview.example.com/x", "target" => [ "preview" ] },
          { "key" => "KV_URL", "type" => "encrypted", "value" => "eyJ2IjoiZW5jcnlwdGVkLXZhbHVlIn0", "target" => "production",
            "contentHint" => { "type" => "redis-url", "storeId" => "store_1" } },
          { "key" => "NEON_API_KEY", "type" => "sensitive", "target" => [ "production" ] },
          { "key" => "SHOWN_BUT_SECRET_URL", "type" => "plain", "visibility" => "secret", "value" => "https://u:secret-visible@api.example.com", "target" => [ "production" ] }
        ], false ])

        snapshot = @pack.map_of(@row)

        uses = snapshot.uses.index_by(&:variable)
        assert_equal %w[DATABASE_URL KV_URL NEON_API_KEY SHOWN_BUT_SECRET_URL], uses.keys.sort
        assert_equal ResourceMap::Fingerprint.of("ep-shop.us-east-2.aws.neon.tech", 5432, @workspace), uses["DATABASE_URL"].fingerprint
        assert [ "KV_URL", "NEON_API_KEY", "SHOWN_BUT_SECRET_URL" ].all? { |name| uses[name].fingerprint.nil? }, "a value Vercel hides is a name only"
        ResourceMap.record!(@row, snapshot)
        assert_no_setting_values(snapshot, plain, "vercel-plain-pw", "ep-shop.us-east-2.aws.neon.tech", "eyJ2IjoiZW5jcnlwdGVkLXZhbHVlIn0", "secret-visible")
      end

      test "settings Vercel refuses are a gap that holds nothing back, and being asked to slow down stops reading them" do
        VercelApi.any_instance.stubs(:project_domains).returns(Integrations::Pages::Read.new(items: [], complete: true))
        VercelApi.any_instance.stubs(:project_env).raises(VercelApi::Error, "Vercel answered 403: Not authorized")

        snapshot = @pack.map_of(@row)
        assert_equal [ [ "The settings of shop could not be read: Vercel answered 403: Not authorized.", [], true ] ],
                     snapshot.gaps.map { |gap| [ gap.text, gap.kinds, gap.settings ] }
        assert snapshot.complete?

        VercelApi.any_instance.stubs(:project_env).raises(VercelApi::Error.new("Vercel answered 429: slow down").extend(Integrations::RateLimited))
        assert_equal [ Vercel::SLOWED ], Vercel.new(@integration).map_of(@row).gaps.map(&:text)
      end

      test "a domain list cut short is a gap, so no domain past it is taken as gone" do
        VercelApi.any_instance.stubs(:project_domains).returns(Integrations::Pages::Read.new(items: [ { "name" => "shop.acme.dev", "verified" => true } ], complete: false))

        snapshot = @pack.map_of(@row)

        assert_equal [ "Only the first 1 domains of shop were read." ], snapshot.gaps.map(&:text)
        assert_equal [ ResourceMap::KIND_DOMAIN ], snapshot.unread_kinds
      end

      test "a change to one project reads that project again, with its repository, domains and settings, and nothing else" do
        VercelApi.any_instance.expects(:projects).never
        VercelApi.any_instance.expects(:project).with("prj_1").returns(
          "id" => "prj_1", "name" => "shop", "accountId" => "team_1", "framework" => "nextjs",
          "link" => { "type" => "github", "org" => "acme", "repo" => "shop", "productionBranch" => "main" },
          "targets" => { "production" => { "id" => "dpl_3", "readyState" => "ERROR", "meta" => { "githubCommitSha" => "d00dfeed" } } }
        )
        VercelApi.any_instance.stubs(:project_domains).with("prj_1").returns(Integrations::Pages::Read.new(items: [ { "name" => "shop.acme.dev", "verified" => true } ], complete: true))
        VercelApi.any_instance.stubs(:project_env).with("prj_1").returns([ [ { "key" => "DATABASE_URL", "type" => "plain", "value" => "postgres://u:p@db.acme.dev/shop", "target" => [ "production" ] } ], false ])

        snapshot = @pack.map_refresh(@row, ResourceMap::Scope.new(account: "team_1", kind: ResourceMap::KIND_SITE, external_id: "prj_1"))

        project = snapshot.resources.find { |found| found.external_id == "prj_1" }
        assert_equal [ "team_1", "error", "d00dfeed" ], [ project.account, project.status, project.details[ResourceMap::DEPLOYED_COMMIT] ]
        assert_equal %w[acme/shop prj_1 shop.acme.dev], snapshot.resources.map(&:external_id).sort
        assert_equal [ "DATABASE_URL" ], snapshot.uses.map(&:variable)
        assert_empty snapshot.gone
      end

      test "a project Vercel answers not found for is gone under the team the change named, and without one the sweep decides" do
        VercelApi.any_instance.stubs(:project).raises(VercelApi::NotFound, "Vercel answered 404: Project not found")
        scope = ResourceMap::Scope.new(account: "team_1", kind: ResourceMap::KIND_SITE, external_id: "prj_old")

        assert_equal [ [ "vercel", "team_1", ResourceMap::KIND_SITE, "prj_old" ] ], @pack.map_refresh(@row, scope).gone
        assert_nil @pack.map_refresh(@row, scope.with(account: nil))
        assert_nil @pack.map_refresh(@row, ResourceMap::Scope.everything)

        VercelApi.any_instance.stubs(:project).raises(VercelApi::Error, "Vercel answered 500: oops")
        assert_raises(VercelApi::Error) { @pack.map_refresh(@row, scope) }
      end

      test "metrics are Observability queries of the project under its owner, production's by default, and a team without Observability Plus is told so" do
        travel_to Time.utc(2026, 10, 20, 12) do
          VercelApi.any_instance.expects(:observability_query).with do |body|
            body == { "scope" => { "type" => "project", "ownerId" => "team_1", "projectIds" => [ "prj_1" ] }, "metric" => "vercel.request.count",
                      "aggregation" => "sum", "startTime" => "2026-10-20T11:00:00Z", "endTime" => "2026-10-20T12:00:00Z",
                      "granularity" => { "minutes" => 1 }, "filter" => "(httpStatus ge 500) and (environment eq 'production')" }
          end.returns("data" => [ { "timestamp" => "2026-10-20T11:00:00Z", "vercel_request_count_sum" => 4 },
                                  { "timestamp" => "2026-10-20T11:01:00Z", "vercel_request_count_sum" => 10 } ])

          result = @pack.call("query_metrics", environment_row: @row, arguments: { "resource" => "shop", "metrics" => [ "http_5xx" ] })

          assert_match "shop, production", result["content"].sole["text"]
          chart = result.dig(Telemetry::STRUCTURED, Telemetry::CHARTS).sole
          assert_equal [ "5xx responses of shop", "requests", [ 4.0, 10.0 ] ], [ chart["title"], chart["unit"], chart["series"].sole["points"].map(&:last) ]
        end

        VercelApi.any_instance.stubs(:observability_query).raises(VercelApi::PlanLimited, "Vercel answered 402: Observability Plus is required")
        refused = assert_raises(NativePack::Error) { call(:query_metrics, "resource" => "shop") }
        assert_match "Observability Plus", refused.message
      end

      test "Vercel's metrics give it no baselines, and the health check lists a project" do
        assert_nil @pack.baselines_of(@row, [], 7.days.ago..Time.current)
        VercelApi.any_instance.stubs(:check!).raises(VercelApi::Error, "Vercel answered 401: invalid token")
        assert_raises(NativePack::Error) { @pack.check_health!(@row) }
      end

      test "deploy history reads a deployment from when it started building to when it was ready or its build failed, named by its target" do
        production = { "uid" => "dpl_2", "target" => "production", "readyState" => "READY", "createdAt" => 1_759_312_800_000,
                       "buildingAt" => 1_759_312_805_000, "ready" => 1_759_312_925_000, "inspectorUrl" => "https://vercel.com/acme/shop/dpl_2" }
        VercelApi.any_instance.stubs(:deployments).with("prj_1", limit: 20, target: nil).returns([
          production, { "uid" => "dpl_1", "readyState" => "ERROR", "createdAt" => 1_759_309_200_000, "errorCode" => "BUILD_FAILED" }
        ])
        VercelApi.any_instance.expects(:deployment).with("dpl_1").returns("id" => "dpl_1", "readyState" => "ERROR", "buildErrorAt" => 1_759_309_290_000)

        runs = Capabilities::History.runs_of(@pack.call("deploy_history", environment_row: @row, arguments: { "resource" => "SHOP" }))

        assert_equal [ [ "production deploy", "succeeded", 120 ], [ "preview deploy", "failed", 90 ] ], runs.map { |run| [ run.name, run.status, run.seconds ] }
        assert_equal "BUILD_FAILED", runs.second.detail

        VercelApi.any_instance.expects(:deployments).with("prj_1", limit: 20, target: "production").returns([ production ])
        only = Capabilities::History.runs_of(@pack.call("deploy_history", environment_row: @row, arguments: { "resource" => "SHOP", "name" => "production" }))
        assert_equal [ "dpl_2" ], only.map(&:id)
      end

      test "a build still running is canceled, and one that ended is refused in words" do
        VercelApi.any_instance.stubs(:deployment).with("dpl_3").returns("id" => "dpl_3", "projectId" => "prj_1", "readyState" => "BUILDING",
                                                                         "creator" => { "uid" => "u1", "username" => "ana", "type" => "user" })
        VercelApi.any_instance.expects(:cancel_deployment).with("dpl_3").returns("id" => "dpl_3", "readyState" => "CANCELED", "inspectorUrl" => "https://vercel.com/acme/shop/3")

        assert_match "Vercel stopped the build of dpl_3 for shop, which is now canceled", call(:cancel_deployment, "resource" => "shop", "deployment" => "dpl_3")
        owner = @pack.owner_of("cancel_deployment", environment_row: @row, arguments: { "resource" => "shop", "deployment" => "dpl_3" })
        assert_equal [ "ana", Owner::ROLE_STARTED, "deployment dpl_3 of shop" ], [ owner.name, owner.role, owner.what ]

        VercelApi.any_instance.stubs(:deployment).with("dpl_2").returns("id" => "dpl_2", "projectId" => "prj_1", "readyState" => "READY")
        assert_match "dpl_2 of shop is ready already, so there is nothing to cancel",
                     assert_raises(NativePack::Error) { call(:cancel_deployment, "resource" => "shop", "deployment" => "dpl_2") }.message
      end

      test "a redeploy builds the deployment again for its own target, or the branch's newest commit" do
        old = { "id" => "dpl_2", "name" => "shop", "projectId" => "prj_1", "target" => "production", "readyState" => "ERROR" }
        VercelApi.any_instance.stubs(:deployment).with("dpl_2").returns(old)
        VercelApi.any_instance.expects(:redeploy).with(old, latest_commit: true).returns("id" => "dpl_9", "inspectorUrl" => "https://vercel.com/acme/shop/9")

        text = call(:redeploy_deployment, "resource" => "shop", "deployment" => "dpl_2", "latest_commit" => true)

        assert_match "Vercel is building dpl_9 for shop, a production deployment from the newest commit of its branch", text
        assert_match "deploy_history with run dpl_9", text
      end

      test "a rolling release is shown by stage, moved on with the next stage's index, completed, or stopped by a rollback to what it replaces" do
        release = { "state" => "ACTIVE", "advancementType" => "manual-approval", "canaryDeployment" => { "id" => "dpl_3", "readyState" => "READY" },
                    "currentDeployment" => { "id" => "dpl_2" }, "stages" => [ {}, {}, {} ],
                    "activeStage" => { "index" => 0, "targetPercentage" => 5, "isFinalStage" => false, "requireApproval" => true },
                    "nextStage" => { "index" => 1, "targetPercentage" => 50, "isFinalStage" => false, "requireApproval" => true } }
        VercelApi.any_instance.stubs(:rolling_release).with("prj_1").returns(release)

        shown = call(:rolling_release, "resource" => "shop")
        assert_match "Rolling release of shop: active, each stage waits for approval", shown
        assert_match "At stage 1 of 3, 5% of production traffic to the new deployment", shown
        assert_match "Next: stage 2, 50% of traffic, waits for approval", shown

        VercelApi.any_instance.expects(:approve_rolling_stage).with("prj_1", next_index: 1, canary_id: "dpl_3").returns("rollingRelease" => release)
        assert_match "moved to stage 2, 50% of production traffic to dpl_3", call(:advance_rolling_release, "resource" => "shop")

        VercelApi.any_instance.expects(:complete_rolling_release).with("prj_1", canary_id: "dpl_3").returns({})
        assert_match "dpl_3 now serves all production traffic of shop", call(:complete_rolling_release, "resource" => "shop")

        VercelApi.any_instance.expects(:rollback).with("prj_1", "dpl_2", description: "Rolling release stopped").returns({})
        assert_match "back to dpl_2, which stops the rolling release of dpl_3", call(:abort_rolling_release, "resource" => "shop")

        VercelApi.any_instance.stubs(:rolling_release).with("prj_1").returns(release.merge("state" => "COMPLETE"))
        assert_match "shop has no rolling release in progress, its last one is complete",
                     assert_raises(NativePack::Error) { call(:advance_rolling_release, "resource" => "shop") }.message
      end

      test "Vercel CI runs are read with their status and timing, and one run by its id has its jobs as parts with their logs" do
        VercelApi.any_instance.expects(:ci_invocations).with(limit: 20, repository: "acme/shop", branch: nil).returns(
          "invocations" => [
            { "invocationId" => "inv_2", "attempt" => 1, "repositoryKey" => "r1", "ref" => "main", "commitSha" => "c4e4267d46e638ac",
              "createdAt" => 1_759_312_800_000, "status" => "awaiting_jobs" },
            { "invocationId" => "inv_1", "attempt" => 1, "repositoryKey" => "r1", "ref" => "main", "commitSha" => "aaaa", "createdAt" => 1_759_309_200_000,
              "status" => "completed", "completed" => { "completedAt" => 1_759_309_500_000, "conclusion" => "failed" } }
          ],
          "repositories" => { "r1" => { "owner" => "acme", "name" => "shop" } }
        )
        runs = Capabilities::History.runs_of(@pack.call("ci_runs", environment_row: @row, arguments: { "repository" => "acme/shop" }))
        assert_equal [ [ "inv_2", "CI acme/shop", "running", nil ], [ "inv_1", "CI acme/shop", "failed", 300 ] ],
                     runs.map { |run| [ run.id, run.name, run.status, run.seconds ] }

        tree = { "invocation" => { "invocationId" => "inv_1", "attempt" => 2, "repositoryKey" => "r1", "createdAt" => 1_759_309_200_000, "status" => "completed",
                                   "completed" => { "completedAt" => 1_759_309_500_000, "conclusion" => "failed" } },
                 "repositories" => { "r1" => { "owner" => "acme", "name" => "shop" } },
                 "jobs" => [ { "definition" => { "jobDefinitionId" => "job_1", "name" => "test" },
                               "run" => { "attempt" => 1, "started" => { "startedAt" => 1_759_309_210_000 },
                                          "completed" => { "completedAt" => 1_759_309_400_000, "conclusion" => { "result" => "failed", "reason" => "exit code 1" } } } } ] }
        VercelApi.any_instance.stubs(:ci_invocation_tree).with("inv_1").returns(tree)
        run = Capabilities::History.runs_of(@pack.call("ci_runs", environment_row: @row, arguments: { "run" => "inv_1" })).sole
        part = run.first_failed_part
        assert_equal [ "test", "failed", "exit code 1", 190 ], [ part.name, part.status, part.detail, part.seconds ]
        assert_equal({ "tool" => "ci_job_log", "arguments" => { "run" => "inv_1", "job" => "job_1" } }, part.log)

        VercelApi.any_instance.expects(:ci_job_logs).with("inv_1", attempt: 2, job_definition_id: "job_1", run_attempt: 1).returns([
          { "level" => "info", "timestamp" => 1_759_309_300_000, "message" => "npm test" },
          { "level" => "error", "timestamp" => 1_759_309_390_000, "message" => "1 test failed" }
        ])
        assert_match "1 test failed", call(:ci_job_log, "run" => "inv_1", "job" => "test")
      end

      test "one deployment is read by its id with its build and checks, the build's log read for that deployment" do
        VercelApi.any_instance.expects(:deployments).never
        VercelApi.any_instance.stubs(:deployment).with("dpl_1").returns(
          "id" => "dpl_1", "projectId" => "prj_1", "target" => "production", "readyState" => "ERROR", "createdAt" => 1_759_309_200_000,
          "buildingAt" => 1_759_309_205_000, "errorCode" => "BUILD_FAILED", "errorMessage" => "Command \"npm run build\" exited with 1",
          "errorStep" => "build", "inspectorUrl" => "https://vercel.com/acme/shop/1", "checksState" => "completed", "checksConclusion" => "skipped",
          "checks" => { "deployment-alias" => { "state" => "succeeded", "startedAt" => 1_759_309_205_000, "completedAt" => 1_759_309_206_000 } }
        )

        run = Capabilities::History.runs_of(@pack.call("deploy_history", environment_row: @row, arguments: { "resource" => "shop", "run" => "dpl_1" })).sole

        assert_equal [ "dpl_1", "failed", "https://vercel.com/acme/shop/1" ], [ run.id, run.status, run.url ]
        assert_equal [ [ "build", "failed" ], [ "checks", "succeeded" ] ], run.parts.map { |part| [ part.name, part.status ] }
        build = run.first_failed_part
        assert_match "at build, BUILD_FAILED", build.detail
        assert_equal({ "tool" => "deployment_logs", "arguments" => { "resource" => "prj_1", "deployment" => "dpl_1", "type" => "build" } }, build.log)
      end

      test "a deployment of another project or one Vercel does not have is said in words, never read as an empty history" do
        VercelApi.any_instance.stubs(:deployment).with("dpl_x").returns("id" => "dpl_x", "projectId" => "prj_other")
        VercelApi.any_instance.stubs(:deployment).with("dpl_gone").raises(VercelApi::NotFound, "Vercel answered 404")

        assert_match "is not a deployment of shop", assert_raises(NativePack::Error) { @pack.call("deploy_history", environment_row: @row, arguments: { "resource" => "shop", "run" => "dpl_x" }) }.message
        assert_match "shop has no deployment dpl_gone", assert_raises(NativePack::Error) { @pack.call("deploy_history", environment_row: @row, arguments: { "resource" => "shop", "run" => "dpl_gone" }) }.message
      end

      test "billing charges add up each day's FOCUS rows by service and by project, and a refusal says the role needs billing" do
        travel_to Time.utc(2026, 10, 10, 12) do
          charges = [
            { "BilledCost" => 4.5, "BillingCurrency" => "USD", "ChargePeriodStart" => "2026-10-08T00:00:00Z", "ServiceName" => "Function Duration",
              "Tags" => { "ProjectName" => "shop" } },
            { "BilledCost" => 1.25, "BillingCurrency" => "USD", "ChargePeriodStart" => "2026-10-08T00:00:00Z", "ServiceName" => "Fast Data Transfer",
              "Tags" => { "ProjectName" => "blog" } },
            { "BilledCost" => 9.0, "BillingCurrency" => "USD", "ChargePeriodStart" => "2026-10-09T00:00:00Z", "ServiceName" => "Function Duration",
              "Tags" => { "ProjectName" => "shop" } }
          ]
          VercelApi.any_instance.expects(:billing_charges).with do |from:, to:, limit:|
            from == Time.utc(2026, 9, 10) && to == Time.current && limit == Vercel::COST_ROWS
          end.returns([ charges, false ])

          text = call(:billing_charges)

          assert_match "in USD:\n- 2026-10-09: 9.00, Function Duration 9.00\n- 2026-10-08: 5.75", text
          assert_match "By project over the whole range:\n- shop: 13.50\n- blog: 1.25", text
        end

        VercelApi.any_instance.stubs(:billing_charges).raises(VercelApi::Refused, "Vercel answered 403: Not authorized")
        refused = assert_raises(Integrations::NativePack::Error) { call(:billing_charges) }
        assert_match "needs to see billing", refused.message
      end

      private

      def call(tool, arguments = {})
        @pack.call(tool.to_s, environment_row: @row, arguments: arguments)["content"].sole["text"]
      end
    end
  end
end
