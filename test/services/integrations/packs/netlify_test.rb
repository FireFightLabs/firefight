require "test_helper"

module Integrations
  module Packs
    class NetlifyTest < ActiveSupport::TestCase
      ADMIN = "https://app.netlify.com/projects/shop".freeze
      SITE = {
        "id" => "site-1", "name" => "shop", "state" => "current", "url" => "http://shop.example.com", "ssl_url" => "https://shop.example.com",
        "admin_url" => ADMIN, "account_id" => "acc-1", "account_slug" => "acme", "custom_domain" => "shop.example.com", "domain_aliases" => [ "www.shop.example.com" ],
        "ssl" => true, "force_ssl" => true, "managed_dns" => false, "password" => "hunter2", "deploy_hook" => "https://api.netlify.com/hooks/secret",
        "build_settings" => { "repo_url" => "https://github.com/acme/shop", "repo_branch" => "main", "cmd" => "npm run build", "dir" => "dist",
                              "env" => { "STRIPE_KEY" => "sk_live_abc" } },
        "published_deploy" => { "id" => "d2", "state" => "ready", "commit_ref" => "abc123def456", "branch" => "main", "title" => "Fix cart\nmore",
                                "published_at" => "2026-10-03T10:00:00Z" }
      }.freeze

      setup do
        @workspace = workspaces(:slack_workspace_one)
        @integration = Integration.create!(workspace: @workspace, kind: Integration::KIND_NATIVE, provider: Netlify::PROVIDER_KEY, name: "Netlify")
        @row = @integration.integration_environments.create!
        Netlify.store_credentials!(@row, Netlify::API_TOKEN => " nfp-token ")
        @pack = Netlify.new(@integration)
        NetlifyApi.any_instance.stubs(:sites).returns(Pages::Read.new(items: [ SITE ], complete: true))
        NetlifyApi.any_instance.stubs(:env_vars).returns([])
      end

      test "the token is stored trimmed, and every tool only reads except putting a site back on an earlier deploy" do
        assert_equal "nfp-token", @row.reload.credentials_hash[Netlify::API_TOKEN]
        assert_equal [ "restore_deploy" ], Netlify.tool_definitions.reject(&:read_only).map(&:name)
      end

      test "a site is found by its id, its name, or a domain it serves" do
        NetlifyApi.any_instance.stubs(:sites).returns(Pages::Read.new(items: [ SITE ], complete: true))
        NetlifyApi.any_instance.stubs(:site).returns(SITE)

        [ SITE["id"], SITE["name"].upcase, SITE["custom_domain"] ].compact.each { |asked| assert @pack.send(:find_site, @row, asked) }
        assert_raises(Integrations::Error) { @pack.send(:find_site, @row, "nowhere") }
      end

      test "a wrong token is said on the form before anything is saved" do
        NetlifyApi.any_instance.stubs(:user).raises(NetlifyApi::Error, "Netlify answered 401: Access Denied")

        assert_equal "Netlify refused this token: Netlify answered 401: Access Denied.", Netlify.credential_refusal({ Netlify::API_TOKEN => "bad" })
        assert_equal "Paste a personal access token.", Netlify.credential_refusal({})
      end

      test "a site is described by its domain, with what it serves and builds from, and never its password, hook or environment" do
        NetlifyApi.any_instance.expects(:site).with("site-1").returns(SITE)

        text = call(:describe_site, "site" => "WWW.shop.example.com")

        assert_match "Live deploy: d2, ready, published 2026-10-03T10:00:00Z, branch main, commit abc123def456, \"Fix cart\"", text
        assert_match "Builds from https://github.com/acme/shop, branch main, command npm run build, publishes dist", text
        assert_match "HTTPS on, forced, DNS elsewhere", text
        assert_no_match(/hunter2|sk_live|hooks\/secret/, text)
        assert text.end_with?("link with what you found: #{ADMIN}")
      end

      test "deploys come newest first with the id a rollback takes, which one is live, and why one failed" do
        NetlifyApi.any_instance.expects(:deploys).with("site-1", limit: 2, production: true, branch: nil).returns([
          { "id" => "d3", "state" => "error", "context" => "production", "branch" => "main", "error_message" => "Build script returned non-zero exit code: 2",
            "created_at" => "2026-10-03T11:00:00Z" },
          { "id" => "d2", "state" => "ready", "context" => "production", "commit_ref" => "abc123def4567890", "created_at" => "2026-10-03T09:58:00Z" }
        ])

        text = call(:list_deploys, "site" => "shop", "production" => true, "limit" => 2)

        assert_match "deploy d3, error, production, branch main, error: Build script returned non-zero exit code: 2", text
        assert_match "deploy d2, ready, live, production, commit abc123def456", text
      end

      test "a deploy's details link to its own page in Netlify" do
        NetlifyApi.any_instance.expects(:deploy).with("site-1", "d2").returns(SITE["published_deploy"].merge(
          "admin_url" => "#{ADMIN}/deploys/d2", "context" => "production", "locked" => true,
          "function_schedules" => [ { "name" => "nightly", "cron" => "0 3 * * *" } ]
        ))

        text = call(:describe_deploy, "site" => "shop", "deploy" => "d2")

        assert_match "Deploy d2 of shop, live now", text
        assert_match "Locked, so auto publishing stays on this deploy", text
        assert_match "Scheduled functions: nightly on 0 3 * * *", text
        assert text.end_with?("#{ADMIN}/deploys/d2")
      end

      test "a restore publishes only a ready deploy of the named site, and says how to undo it" do
        NetlifyApi.any_instance.stubs(:deploy).with("site-1", "d1").returns("id" => "d1", "state" => "ready")
        NetlifyApi.any_instance.expects(:restore).with("site-1", "d1").returns("id" => "d1", "admin_url" => "#{ADMIN}/deploys/d1")

        text = call(:restore_deploy, "site" => "shop", "deploy" => "d1")

        assert_match "shop now serves deploy d1. To undo it, restore deploy d2, which was live before.", text
        assert text.end_with?("#{ADMIN}/deploys/d1")

        NetlifyApi.any_instance.stubs(:deploy).with("site-1", "d3").returns("id" => "d3", "state" => "error")
        NetlifyApi.any_instance.expects(:restore).with("site-1", "d3").never
        assert_match "only a ready deploy", assert_raises(NativePack::Error) { call(:restore_deploy, "site" => "shop", "deploy" => "d3") }.message
        assert_raises(NativePack::Error) { call(:restore_deploy, "site" => "elsewhere", "deploy" => "d1") }
      end

      test "the map holds each site with the domains it serves and the repository it builds from" do
        snapshot = @pack.map_of(@row)

        site = snapshot.resources.find { |resource| resource.kind == ResourceMap::KIND_SITE }
        assert_equal [ "acme", "site-1", "shop", "current", ADMIN ], [ site.account, site.external_id, site.name, site.status, site.url ]
        assert_equal "abc123def456", site.details[ResourceMap::DEPLOYED_COMMIT]
        relations = snapshot.links.map { |link| [ link.from.last, link.relation, link.to.last ] }
        assert_includes relations, [ "shop.example.com", ResourceMap::RELATION_SERVED_BY, "site-1" ]
        assert_includes relations, [ "www.shop.example.com", ResourceMap::RELATION_SERVED_BY, "site-1" ]
        assert_includes relations, [ "site-1", ResourceMap::RELATION_BUILT_FROM, "acme/shop" ]
        assert_empty snapshot.gaps
      end

      test "a site's settings are read in memory, the production value first, and a secret by its name" do
        NetlifyApi.any_instance.expects(:env_vars).with("acc-1", "site-1").returns([
          { "key" => "DATABASE_URL", "is_secret" => false,
            "values" => [ { "context" => "deploy-preview", "value" => "postgres://u:preview-pass@preview.example.com/app" },
                          { "context" => "production", "value" => "postgres://u:prod-pass@db.example.com/app" } ] },
          { "key" => "SUPABASE_SERVICE_KEY", "is_secret" => true, "values" => [ { "context" => "dev", "value" => "dev-only-secret" } ] },
          { "key" => "THEME", "values" => [ { "context" => "all", "value" => "dark" } ] }
        ])

        snapshot = @pack.map_of(@row)

        uses = snapshot.uses.index_by(&:variable)
        assert_equal %w[DATABASE_URL SUPABASE_SERVICE_KEY], uses.keys.sort
        assert_equal ResourceMap::Fingerprint.of("db.example.com", 5432, @workspace), uses["DATABASE_URL"].fingerprint
        assert_nil uses["SUPABASE_SERVICE_KEY"].fingerprint
        assert_empty snapshot.gaps
        assert_no_setting_values(snapshot, "prod-pass", "preview-pass", "db.example.com", "dev-only-secret")
      end

      test "settings Netlify refuses or is slow to give are a gap that keeps the ones read before, and no site is held back" do
        NetlifyApi.any_instance.stubs(:env_vars).raises(NetlifyApi::Error, "Netlify answered 403: forbidden")

        snapshot = @pack.map_of(@row)

        assert_equal [ "Netlify refused the settings of shop: Netlify answered 403: forbidden. Firefight tries again at the next sweep." ], snapshot.gaps.map(&:text)
        assert snapshot.complete?
        assert_not snapshot.settings_complete?

        NetlifyApi.any_instance.stubs(:env_vars).raises(NetlifyApi::Error.new("Netlify answered 429").extend(Integrations::RateLimited))
        assert_match(/slow down/, @pack.map_of(@row).gaps.sole.text)
      end

      test "a map cut short says so and takes no site as gone" do
        NetlifyApi.any_instance.stubs(:sites).returns(Pages::Read.new(items: [ SITE ], complete: false))

        snapshot = @pack.map_of(@row)

        assert_equal [ "Only the first 1 sites were read." ], snapshot.gaps.map(&:text)
        assert_equal [ ResourceMap::KIND_SITE, ResourceMap::KIND_DOMAIN, ResourceMap::KIND_REPOSITORY ], snapshot.unread_kinds, "a site's domains and repository go with it"
      end

      test "the health check reads the token's user and records Netlify's refusal" do
        NetlifyApi.any_instance.stubs(:user).raises(NetlifyApi::Error, "Netlify answered 401: Access Denied")

        assert_raises(NativePack::Error) { @pack.check_health!(@row) }
      end

      private

      def call(tool, arguments = {})
        @pack.call(tool.to_s, environment_row: @row, arguments: arguments)["content"].sole["text"]
      end
    end
  end
end
