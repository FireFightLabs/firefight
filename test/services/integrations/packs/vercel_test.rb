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

      test "the token and team are stored trimmed, and only the rollback and promotion change anything" do
        assert_equal "tok", ConnectionSettings.of(@row.reload).credential(Vercel::API_TOKEN)
        assert_equal %w[rollback_deployment promote_deployment], Vercel.tool_definitions.reject(&:read_only).map(&:name)
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

      test "Vercel keeps no metrics the API reads, so it has no baselines, and the health check lists a project" do
        assert_nil @pack.baselines_of(@row, [], 7.days.ago..Time.current)
        VercelApi.any_instance.stubs(:check!).raises(VercelApi::Error, "Vercel answered 401: invalid token")
        assert_raises(NativePack::Error) { @pack.check_health!(@row) }
      end

      private

      def call(tool, arguments = {})
        @pack.call(tool.to_s, environment_row: @row, arguments: arguments)["content"].sole["text"]
      end
    end
  end
end
