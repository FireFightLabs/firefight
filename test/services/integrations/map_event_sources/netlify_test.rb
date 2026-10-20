require "test_helper"

module Integrations
  module MapEventSources
    class NetlifyTest < ActiveSupport::TestCase
      SECRET = "netlify-hook-secret".freeze
      URL = "https://firefight.example.com/api/v1/map_events/token-1".freeze
      TYPES = [ { "name" => "url", "events" => %w[deploy_building deploy_created deploy_failed deploy_restored], "restricted_events" => [] },
                { "name" => "email", "events" => %w[deploy_created] } ].freeze

      setup do
        @workspace = workspaces(:slack_workspace_one)
        @integration = Integration.create!(workspace: @workspace, kind: Integration::KIND_NATIVE, provider: "netlify", name: "Netlify")
        @row = @integration.integration_environments.create!
        Packs::Netlify.store_credentials!(@row, Packs::Netlify::API_TOKEN => "nfp-token")
        NetlifyApi.any_instance.stubs(:sites).returns(Pages::Read.new(items: [ site("site-1"), site("site-2") ], complete: true))
        NetlifyApi.any_instance.stubs(:hook_types).returns(TYPES)
      end

      test "a delivery is Netlify's when its JWS is HS256 with the hook's secret, issued by netlify and naming the body's digest" do
        body = deploy.to_json

        assert Netlify.verify(raw_body: body, headers: signed(body), secret: SECRET)
        assert_not Netlify.verify(raw_body: body.sub("site-1", "site-9"), headers: signed(body), secret: SECRET), "another body"
        assert_not Netlify.verify(raw_body: body, headers: signed(body, secret: "another"), secret: SECRET)
        assert_not Netlify.verify(raw_body: body, headers: signed(body, issuer: "someone"), secret: SECRET)
        assert_not Netlify.verify(raw_body: body, headers: { "x-webhook-signature" => JWT.encode({ "iss" => "netlify", "sha256" => Digest::SHA256.hexdigest(body) }, nil, "none") }, secret: SECRET)
        assert_not Netlify.verify(raw_body: body, headers: {}, secret: SECRET)
        assert_not Netlify.verify(raw_body: body, headers: signed(body), secret: nil)
      end

      test "a production deploy published or restored names its site, and a preview or another event names nothing" do
        published = Netlify.events(deploy, headers: { "x-netlify-event" => "deploy_created" }).sole

        assert_equal ResourceMap::Scope.new(kind: ResourceMap::KIND_SITE, external_id: "site-1"), published.scope
        assert_equal [ "deploy_created:d3:2026-10-06T10:00:00Z", Time.iso8601("2026-10-06T10:01:00Z") ], [ published.id, published.at ]
        assert_equal "site-1", Netlify.events(deploy, headers: { "x-netlify-event" => "deploy_restored" }).sole.scope.external_id
        assert_empty Netlify.events(deploy.merge("context" => "deploy-preview"), headers: { "x-netlify-event" => "deploy_created" })
        assert_empty Netlify.events(deploy, headers: { "x-netlify-event" => "deploy_building" })
        assert_empty Netlify.events(deploy, headers: {})
      end

      test "registering adds a hook for each event the plan offers to every site, signed with the connection's one secret" do
        NetlifyApi.any_instance.stubs(:hooks).with("site-1").returns([ { "id" => "theirs", "type" => "url", "event" => "deploy_created", "data" => { "url" => "https://example.com" } } ])
        NetlifyApi.any_instance.stubs(:hooks).with("site-2").returns([])
        made = []
        NetlifyApi.any_instance.stubs(:create_hook).with { |site, **options| made << [ site, options[:event], options[:url], options[:secret] ] }.returns({})
        NetlifyApi.any_instance.expects(:delete_hook).never

        webhook = Netlify.register(@row, url: URL)

        secret = @row.reload.map_events_secret
        assert_equal 64, secret.size
        assert_equal [ Netlify::ALL_SITES, secret ], [ webhook.id, webhook.secret ]
        offered = %w[deploy_created deploy_restored deploy_building deploy_failed]
        assert_equal %w[site-1 site-2].flat_map { |site| offered.map { |event| [ site, event, URL, secret ] } }, made
        assert_equal offered + Netlify::DEPLOY_REQUESTS, Netlify::EVENTS
      end

      test "a deploy waiting for approval, accepted or rejected gets a hook where the plan offers it, and wakes a watch without touching the map" do
        NetlifyApi.any_instance.stubs(:hook_types).returns([ { "name" => "url", "events" => Netlify::EVENTS, "restricted_events" => [] } ])
        NetlifyApi.any_instance.stubs(:hooks).returns([])
        made = []
        NetlifyApi.any_instance.stubs(:create_hook).with { |site, **options| made << [ site, options[:event] ] }.returns({})

        Netlify.register(@row, url: URL)

        assert_equal %w[site-1 site-2].flat_map { |site| Netlify::DEPLOY_REQUESTS.map { |event| [ site, event ] } }, made.select { |_site, event| event.start_with?("deploy_request") }
        assert Netlify.wakes?(deploy.merge("state" => "pending_review"), headers: { "x-netlify-event" => "deploy_request_pending" })
        assert_empty Netlify.events(deploy, headers: { "x-netlify-event" => "deploy_request_accepted" })
      end

      test "registering again takes back Firefight's hooks at this address, turning on one Netlify disabled, and adds only what is missing" do
        @row.update!(map_events_secret: SECRET)
        NetlifyApi.any_instance.stubs(:hooks).with("site-1").returns([ own("h1", "deploy_created"), own("h2", "deploy_restored", disabled: true), *run_hooks("site-1") ])
        NetlifyApi.any_instance.stubs(:hooks).with("site-2").returns([ own("h3", "deploy_created"), *run_hooks("site-2") ])
        NetlifyApi.any_instance.expects(:enable_hook).with("h2").returns({})
        NetlifyApi.any_instance.expects(:create_hook).with("site-2", event: "deploy_restored", url: URL, secret: SECRET).returns({})

        assert Netlify.register_again?(@row, url: URL)
        assert_equal SECRET, Netlify.register(@row, url: URL).secret

        NetlifyApi.any_instance.stubs(:hooks).with("site-1").returns([ own("h1", "deploy_created"), own("h2", "deploy_restored"), *run_hooks("site-1") ])
        NetlifyApi.any_instance.stubs(:hooks).with("site-2").returns([ own("h3", "deploy_created"), own("h4", "deploy_restored"), *run_hooks("site-2") ])
        assert_not Netlify.register_again?(@row, url: URL)
      end

      test "a connection registered before deploys starting and failing were followed gets their hooks at the next sweep" do
        @row.update!(map_events_secret: SECRET)
        NetlifyApi.any_instance.stubs(:hooks).with("site-1").returns([ own("h1", "deploy_created"), own("h2", "deploy_restored") ])
        NetlifyApi.any_instance.stubs(:hooks).with("site-2").returns([ own("h3", "deploy_created"), own("h4", "deploy_restored") ])
        made = []
        NetlifyApi.any_instance.stubs(:create_hook).with { |site, **options| made << [ site, options[:event] ] }.returns({})

        assert Netlify.register_again?(@row, url: URL)
        Netlify.register(@row, url: URL)

        assert_equal [ [ "site-1", "deploy_building" ], [ "site-1", "deploy_failed" ], [ "site-2", "deploy_building" ], [ "site-2", "deploy_failed" ] ], made
      end

      test "any deploy starting, failing, publishing or restored wakes watches, a preview's too, while only production reaches the map" do
        preview = deploy.merge("context" => "deploy-preview", "state" => "error", "error_message" => "Build script returned non-zero exit code: 2")
        Netlify::EVENTS.each { |event| assert Netlify.wakes?(preview, headers: { "x-netlify-event" => event }), event }
        assert_empty Netlify.events(preview, headers: { "x-netlify-event" => "deploy_failed" })
        assert_empty Netlify.events(deploy, headers: { "x-netlify-event" => "deploy_failed" })
        assert_not Netlify.wakes?(deploy, headers: { "x-netlify-event" => "submission_created" })
        assert_not Netlify.wakes?(deploy.except("site_id"), headers: { "x-netlify-event" => "deploy_failed" })
      end

      test "an event the plan restricts gets no hook, and a team whose plan offers none is refused for the plan" do
        NetlifyApi.any_instance.stubs(:hook_types).returns([ { "name" => "url", "events" => %w[deploy_created deploy_restored], "restricted_events" => %w[deploy_created] } ])
        NetlifyApi.any_instance.stubs(:hooks).returns([])
        NetlifyApi.any_instance.expects(:create_hook).twice.with { |_site, **options| options[:event] == "deploy_restored" }.returns({})
        Netlify.register(@row, url: URL)

        NetlifyApi.any_instance.stubs(:hook_types).returns([ { "name" => "url", "events" => %w[deploy_created], "restricted_events" => %w[deploy_created] } ])
        error = assert_raises(MapEventSource::Refused) { Netlify.register(@row, url: URL) }
        assert_equal "#{Netlify::REFUSED}.", error.message

        NetlifyApi.any_instance.stubs(:hook_types).raises(NetlifyApi::Refused, "Netlify answered 403: forbidden")
        assert_equal "Netlify answered 403: forbidden. #{Netlify::REFUSED}.", assert_raises(MapEventSource::Refused) { Netlify.register(@row, url: URL) }.message
      end

      test "removing takes back every hook at this address on every site, and one already gone all the same" do
        NetlifyApi.any_instance.stubs(:hooks).with("site-1").returns([ own("h1", "deploy_created"), { "id" => "theirs", "type" => "url", "data" => { "url" => "https://example.com" } } ])
        NetlifyApi.any_instance.stubs(:hooks).with("site-2").returns([ own("h3", "deploy_created") ])
        NetlifyApi.any_instance.expects(:delete_hook).with("h1").returns({})
        NetlifyApi.any_instance.expects(:delete_hook).with("h3").raises(NetlifyApi::NotFound, "Netlify answered 404: not found")
        NetlifyApi.any_instance.expects(:delete_hook).with("theirs").never

        Integrations::MapEvents.stubs(:url_for).with(@row).returns(URL)
        Netlify.remove(@row, Netlify::ALL_SITES)
      end

      private

      def site(id) = { "id" => id, "name" => id, "account_id" => "acc-1" }

      def own(id, event, disabled: false) = { "id" => id, "type" => "url", "event" => event, "disabled" => disabled, "data" => { "url" => URL } }

      def run_hooks(site) = [ own("#{site}-b", "deploy_building"), own("#{site}-f", "deploy_failed") ]

      def deploy
        { "id" => "d3", "site_id" => "site-1", "context" => "production", "state" => "ready", "updated_at" => "2026-10-06T10:00:00Z",
          "published_at" => "2026-10-06T10:01:00Z" }
      end

      def signed(body, secret: SECRET, issuer: "netlify")
        { "x-webhook-signature" => JWT.encode({ "iss" => issuer, "sha256" => Digest::SHA256.hexdigest(body) }, secret, "HS256") }
      end
    end
  end
end
