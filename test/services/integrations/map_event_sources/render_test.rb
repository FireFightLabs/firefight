require "test_helper"

module Integrations
  module MapEventSources
    class RenderTest < ActiveSupport::TestCase
      include LiveUpdatesTestHelper

      # The deploy_ended payload Render's docs show (render.com/docs/webhooks, Request body), and a secret in the form the
      # standardwebhooks library reads, its prefix then base64.
      SAMPLE = { "type" => "deploy_ended", "timestamp" => "2025-02-25T16:22:19.979294509Z",
                 "data" => { "id" => "evt-cuuuses015js70180jk0", "serviceId" => "srv-cukouhrtq21c73e9scng", "serviceName" => "my-service",
                             "status" => "succeeded" } }.freeze
      SECRET = "whsec_#{Base64.strict_encode64('render signing key')}".freeze
      URL = "https://firefight.example.com/api/v1/map_events/token-1".freeze

      setup do
        @workspace = workspaces(:slack_workspace_one)
        @integration = Integration.create!(workspace: @workspace, kind: Integration::KIND_NATIVE, provider: "render", name: "Render")
        @row = @integration.integration_environments.create!
        Packs::Render.store_credentials!(@row, Packs::Render::API_KEY => "rnd_key")
        @row.store_fields!(Packs::Render::WORKSPACE => "tea-1")
        RenderApi.any_instance.expects(:delete_webhook).never
      end

      test "a delivery signed as Standard Webhooks says is Render's, and one signed otherwise, stale or unsigned is not" do
        body = SAMPLE.to_json
        headers = signed(body)

        assert Render.verify(raw_body: body, headers: headers, secret: SECRET)
        assert Render.verify(raw_body: body, headers: headers.merge("webhook-signature" => "v1,bm90IGl0 #{headers['webhook-signature']}"), secret: SECRET),
               "any one of the signatures Render sends is enough"
        assert_not Render.verify(raw_body: body, headers: headers, secret: "whsec_#{Base64.strict_encode64('another key')}")
        assert_not Render.verify(raw_body: body.sub("succeeded", "failed"), headers: headers, secret: SECRET)
        assert_not Render.verify(raw_body: body, headers: signed(body, at: 6.minutes.ago), secret: SECRET)
        assert_not Render.verify(raw_body: body, headers: signed(body, at: 6.minutes.from_now), secret: SECRET)
        assert Render.verify(raw_body: body, headers: signed(body, at: 4.minutes.ago), secret: SECRET)
        assert_not Render.verify(raw_body: body, headers: headers.except("webhook-signature"), secret: SECRET)
        assert_not Render.verify(raw_body: body, headers: headers.merge("webhook-signature" => headers["webhook-signature"].sub("v1,", "v2,")), secret: SECRET)
        assert_not Render.verify(raw_body: body, headers: headers, secret: nil)
      end

      test "the signature matches the Standard Webhooks specification's own example" do
        # The example in the specification (standard-webhooks/standard-webhooks, spec/standard-webhooks.md, Verifying signatures).
        headers = { "webhook-id" => "msg_p5jXN8AQM9LWM0D4loKWxJek", "webhook-timestamp" => "1614265330",
                    "webhook-signature" => "v1,g0hM9SsE+OTPJTGt/tmIKtSyZlE3uFJELVlNIOLJ1OE=" }

        travel_to Time.zone.at(1_614_265_330) do
          assert Render.verify(raw_body: '{"test": 2432232314}', headers: headers, secret: "whsec_MfKQ9r8GKYqrTwjUPD8ILPZIo2LaLaSw")
        end
      end

      test "a service's event names the service, a datastore's the datastore, and an event the map does not show nothing" do
        deploy = Render.events(SAMPLE, headers: {}).sole

        assert_equal [ "evt-cuuuses015js70180jk0", ResourceMap::Event::UPDATED, Time.iso8601("2025-02-25T16:22:19.979294509Z") ], [ deploy.id, deploy.action, deploy.at ]
        assert_equal ResourceMap::Scope.new(external_id: "srv-cukouhrtq21c73e9scng"), deploy.scope

        created = Render.events({ "type" => "postgres_created", "timestamp" => "2026-10-01T10:00:00Z", "data" => { "id" => "evt-2", "serviceId" => "dpg-1" } }, headers: {}).sole
        assert_equal [ ResourceMap::Event::ADDED, ResourceMap::Scope.new(kind: ResourceMap::KIND_DATABASE, external_id: "dpg-1") ], [ created.action, created.scope ]
        unhealthy = Render.events({ "type" => "key_value_unhealthy", "timestamp" => "2026-10-01T10:00:00Z", "data" => { "id" => "evt-3", "serviceId" => "red-1" } }, headers: {}).sole
        assert_equal ResourceMap::Scope.new(kind: ResourceMap::KIND_DATABASE, external_id: "red-1"), unhealthy.scope

        assert_empty Render.events(SAMPLE.merge("type" => "cron_job_run_ended"), headers: {})
        assert_empty Render.events(SAMPLE.merge("data" => {}), headers: {})
        assert_equal "evt-from-header", Render.events(SAMPLE.merge("data" => { "serviceId" => "srv-1" }), headers: { "webhook-id" => "evt-from-header" }).sole.id
      end

      test "registering adds a webhook for the events the map reads, beside one at another address that it leaves alone" do
        RenderApi.any_instance.stubs(:webhooks).with("tea-1").returns(Pages::Read.new(items: [ webhook("whk-theirs", "https://example.com/hook") ], complete: true))
        RenderApi.any_instance.expects(:enable_webhook).never
        RenderApi.any_instance.expects(:create_webhook).with("tea-1", name: Render::WEBHOOK_NAME, url: URL, events: Render::EVENTS)
                  .returns(webhook("whk-ours", URL).merge("secret" => SECRET))

        assert_equal Render::Webhook.new(id: "whk-ours", secret: SECRET), Render.register(@row, url: URL)
        assert_includes Render::EVENTS, "deploy_ended"
        assert_includes Render::EVENTS, "postgres_available"
      end

      test "a webhook Firefight registered before at this address is taken back, and switched on again if Render switched it off" do
        RenderApi.any_instance.stubs(:webhooks).returns(Pages::Read.new(items: [ webhook("whk-ours", URL, enabled: false) ], complete: true))
        RenderApi.any_instance.expects(:create_webhook).never
        RenderApi.any_instance.expects(:enable_webhook).with("whk-ours").returns(webhook("whk-ours", URL))

        assert_equal Render::Webhook.new(id: "whk-ours", secret: SECRET), Render.register(@row, url: URL)
      end

      test "a workspace whose plan has no room for a webhook is told why, and its own webhook is never touched" do
        RenderApi.any_instance.stubs(:webhooks).returns(Pages::Read.new(items: [ webhook("whk-theirs", "https://example.com/hook") ], complete: true))
        RenderApi.any_instance.stubs(:create_webhook).raises(RenderApi::Refused, "Render answered 400: webhook limit reached")
        RenderApi.any_instance.expects(:enable_webhook).never

        refusal = assert_raises(MapEventSource::Refused) { Render.register(@row, url: URL) }

        assert_equal "Render answered 400: webhook limit reached. #{Render::PLAN_NOTE}.", refusal.message
      end

      test "a person decides when Firefight's webhook could be the workspace's only one or its last, from how many it has" do
        theirs = ->(count) { Pages::Read.new(items: Array.new(count) { |index| webhook("whk-#{index}", "https://example.com/#{index}") }, complete: true) }

        RenderApi.any_instance.stubs(:webhooks).with("tea-1").returns(theirs.call(0))
        assert_equal Render::ONLY_WEBHOOK, Render.confirmation_for(@row, url: URL)
        RenderApi.any_instance.stubs(:webhooks).with("tea-1").returns(theirs.call(1))
        assert_nil Render.confirmation_for(@row, url: URL), "a second webhook means room to spare, or a refusal Render gives for Pro"
        RenderApi.any_instance.stubs(:webhooks).with("tea-1").returns(theirs.call(99))
        assert_equal "This Render workspace has 99 webhooks and Render allows 100, so Firefight's would be the last one the workspace can add.",
                     Render.confirmation_for(@row, url: URL)
        RenderApi.any_instance.stubs(:webhooks).with("tea-1").returns(Pages::Read.new(items: [ webhook("whk-ours", URL) ], complete: true))
        assert_nil Render.confirmation_for(@row, url: URL), "Firefight's own from before costs nothing"

        RenderApi.any_instance.stubs(:webhooks).raises(RenderApi::Refused, "Render answered 403: upgrade to use webhooks")
        assert_raises(MapEventSource::Refused) { Render.confirmation_for(@row, url: URL) }
      end

      test "removing takes back Firefight's webhook, and one Render no longer has is done" do
        RenderApi.any_instance.unstub(:delete_webhook)
        RenderApi.any_instance.expects(:delete_webhook).with("whk-ours").returns({})
        Render.remove(@row, "whk-ours")

        RenderApi.any_instance.stubs(:delete_webhook).raises(RenderApi::NotFound, "Render answered 404: not found")
        assert_nil Render.remove(@row, "whk-gone")
      end

      private

      def signed(body, at: Time.current, id: "evt-cuuuses015js70180jk0")
        key = Base64.decode64(SECRET.delete_prefix("whsec_"))
        signature = Base64.strict_encode64(OpenSSL::HMAC.digest("SHA256", key, "#{id}.#{at.to_i}.#{body}"))
        { "webhook-id" => id, "webhook-timestamp" => at.to_i.to_s, "webhook-signature" => "v1,#{signature}" }
      end

      def webhook(id, url, enabled: true) = { "id" => id, "url" => url, "name" => "hook", "enabled" => enabled, "secret" => SECRET, "eventFilter" => [] }
    end
  end
end
