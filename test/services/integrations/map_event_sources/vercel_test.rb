require "test_helper"

module Integrations
  module MapEventSources
    class VercelTest < ActiveSupport::TestCase
      SECRET = "vercel-webhook-secret".freeze
      URL = "https://firefight.example.com/api/v1/map_events/token-1".freeze

      setup do
        @workspace = workspaces(:slack_workspace_one)
        @integration = Integration.create!(workspace: @workspace, kind: Integration::KIND_NATIVE, provider: "vercel", name: "Vercel")
        @row = @integration.integration_environments.create!
        Packs::Vercel.store_credentials!(@row, Packs::Vercel::API_TOKEN => "tok")
        @row.store_fields!(Packs::Vercel::TEAM => "team_1")
      end

      test "a delivery whose x-vercel-signature is the HMAC-SHA1 of its body with the webhook's secret is Vercel's, and no other is" do
        body = delivery("deployment.succeeded", "deployment" => { "id" => "dpl_2" }, "target" => "production").to_json
        signature = OpenSSL::HMAC.hexdigest("SHA1", SECRET, body)

        assert Vercel.verify(raw_body: body, headers: { "x-vercel-signature" => signature }, secret: SECRET)
        assert_not Vercel.verify(raw_body: body, headers: { "x-vercel-signature" => OpenSSL::HMAC.hexdigest("SHA1", "another", body) }, secret: SECRET)
        assert_not Vercel.verify(raw_body: body.sub("dpl_2", "dpl_3"), headers: { "x-vercel-signature" => signature }, secret: SECRET)
        assert_not Vercel.verify(raw_body: body, headers: {}, secret: SECRET)
        assert_not Vercel.verify(raw_body: body, headers: { "x-vercel-signature" => OpenSSL::HMAC.hexdigest("SHA1", "", body) }, secret: nil)
      end

      test "a production deployment, a promotion and a project's own changes each name the project, and a preview names nothing" do
        succeeded = Vercel.events(delivery("deployment.succeeded", "deployment" => { "id" => "dpl_2" }, "target" => "production"), headers: {}).sole

        assert_equal [ "evt_1", ResourceMap::Event::UPDATED, Time.zone.at(1_700_000_000) ], [ succeeded.id, succeeded.action, succeeded.at ]
        assert_equal ResourceMap::Scope.new(account: "team_1", kind: ResourceMap::KIND_SITE, external_id: "prj_1"), succeeded.scope
        assert_empty Vercel.events(delivery("deployment.created", "deployment" => { "id" => "dpl_3" }, "target" => nil), headers: {})
        assert_equal ResourceMap::Event::UPDATED, Vercel.events(delivery("deployment.promoted"), headers: {}).sole.action
        assert_equal ResourceMap::Event::UPDATED, Vercel.events(delivery("deployment.rollback", "fromDeploymentId" => "dpl_2", "toDeploymentId" => "dpl_1"), headers: {}).sole.action
        assert_equal ResourceMap::Event::ADDED, Vercel.events(delivery("project.created"), headers: {}).sole.action
        assert_equal ResourceMap::Event::REMOVED, Vercel.events(delivery("project.removed"), headers: {}).sole.action

        setting = Vercel.events(delivery("project.env-variable.updated", "project" => nil, "projectId" => "prj_9", "envVarId" => "env_1"), headers: {}).sole
        assert_equal "prj_9", setting.scope.external_id
        assert_empty Vercel.events(delivery("flag.created"), headers: {})
      end

      test "a domain joining a project reads the project, and one leaving, moving or changing sweeps the connection" do
        added = Vercel.events(delivery("project.domain.created", "domain" => { "name" => "shop.acme.dev" }), headers: {}).sole
        assert_equal [ ResourceMap::Event::LINKED, "prj_1" ], [ added.action, added.scope.external_id ]

        Vercel::DOMAIN_CHANGED_EVENTS.each do |type|
          changed = Vercel.events(delivery(type, "domain" => { "name" => "shop.acme.dev" }), headers: {}).sole
          assert changed.rescope?, "#{type} sweeps"
          assert changed.scope.everything?
        end
      end

      test "registering adds a webhook for every project in the team, deleting only one Firefight left at this same address" do
        VercelApi.any_instance.stubs(:webhooks).returns([ { "id" => "hook_theirs", "url" => "https://example.com/hook" }, { "id" => "hook_old", "url" => URL } ])
        VercelApi.any_instance.expects(:delete_webhook).with("hook_old").returns({})
        VercelApi.any_instance.expects(:delete_webhook).with("hook_theirs").never
        VercelApi.any_instance.expects(:create_webhook).with(url: URL, events: Vercel::EVENTS).returns("id" => "hook_new", "secret" => SECRET)

        assert_equal MapEventSource::Webhook.new(id: { "team_1" => "hook_new" }.to_json, secret: SECRET, scopes: [ "team_1" ]), Vercel.register(@row, url: URL)
      end

      test "a team whose plan cannot have webhooks, or has no room, is told why, and no webhook is touched" do
        VercelApi.any_instance.stubs(:webhooks).returns([ { "id" => "hook_theirs", "url" => "https://example.com/hook" } ])
        VercelApi.any_instance.expects(:delete_webhook).never
        VercelApi.any_instance.stubs(:create_webhook).raises(VercelApi::Refused, "Vercel answered 403: Webhooks are not available on the Hobby plan")

        refusal = assert_raises(MapEventSource::Refused) { Vercel.register(@row, url: URL) }

        assert_equal "Vercel answered 403: Webhooks are not available on the Hobby plan. #{Vercel::PLAN_NOTE}.", refusal.message
      end

      test "removing takes back Firefight's webhook, and one Vercel no longer has is done" do
        VercelApi.any_instance.expects(:delete_webhook).with("hook_new").returns({})
        Vercel.remove(@row, "hook_new")

        VercelApi.any_instance.stubs(:delete_webhook).raises(VercelApi::NotFound, "Vercel answered 404: not found")
        assert_nothing_raised { Vercel.remove(@row, { "team_1" => "hook_gone" }.to_json) }
      end

      private

      # A delivery in the shape Vercel's docs give (vercel.com/docs/webhooks, Events, and webhooks-api, Supported Event Types).
      def delivery(type, **payload)
        { "id" => "evt_1", "type" => type, "createdAt" => 1_700_000_000_000, "region" => nil,
          "payload" => { "team" => { "id" => "team_1" }, "user" => { "id" => "user_1" }, "project" => { "id" => "prj_1" } }.merge(payload.stringify_keys) }
      end
    end
  end
end
