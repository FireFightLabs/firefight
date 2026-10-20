require "test_helper"

module Integrations
  module MapEventSources
    class ConvexTest < ActiveSupport::TestCase
      URL = "https://firefight.example.com/api/v1/map_events/token-1".freeze
      SECRET = "hmac-secret".freeze

      setup do
        @workspace = workspaces(:slack_workspace_one)
        integration = Integration.create!(workspace: @workspace, kind: Integration::KIND_NATIVE, provider: "convex", name: "Convex")
        @row = integration.integration_environments.create!
        Packs::Convex.store_credentials!(@row, Packs::Convex::DEPLOY_KEY => "prod:happy-animal-123|key")
        @row.store_fields!(Packs::Convex::DEPLOYMENT_URL => "https://happy-animal-123.convex.cloud")
        travel_to Time.zone.parse("2026-10-04T12:00:00Z")
      end

      test "a delivery signed with the stream's secret as Convex documents is Convex's, and one signed otherwise or unsigned is not" do
        body = [ audit("push_config") ].to_json
        signed = { "x-webhook-signature" => "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', SECRET, body)}" }

        assert_equal Convex, MapEvents.source_of("convex")
        assert Convex.verify(raw_body: body, headers: signed, secret: SECRET)
        assert_not Convex.verify(raw_body: body, headers: signed, secret: "other")
        assert_not Convex.verify(raw_body: body.sub("push", "pull"), headers: signed, secret: SECRET)
        assert_not Convex.verify(raw_body: body, headers: { "x-webhook-signature" => signed["x-webhook-signature"].delete_prefix("sha256=") }, secret: SECRET)
        assert_not Convex.verify(raw_body: body, headers: {}, secret: SECRET)
        assert_not Convex.verify(raw_body: body, headers: signed, secret: nil)
      end

      test "each recent audit log entry reads the deployment again, a retry is the same event, and anything else is ignored" do
        payload = [ audit("push_config"), audit("pause_deployment", at: 10.minutes.ago), { "topic" => "console", "timestamp" => Time.current.to_i * 1000 },
                    { "topic" => "verification" } ]

        event = Convex.events(payload, headers: {}).sole

        assert_equal [ ResourceMap::Event::UPDATED, ResourceMap::Scope.new(kind: ResourceMap::KIND_SERVICE, external_id: "happy-animal-123") ],
                     [ event.action, event.scope ]
        assert_equal event.provider_id, Convex.events(payload, headers: {}).sole.provider_id
        assert_empty Convex.events({ "topic" => "audit_log" }, headers: {})
      end

      test "registering adds a webhook stream for the audit log, keeps Firefight's own, and never replaces the team's" do
        ConvexApi.any_instance.stubs(:log_streams).returns([ { "logStreamType" => "datadog", "id" => "dd" } ])
        ConvexApi.any_instance.expects(:create_webhook_stream).with(url: URL, topics: [ "audit_log" ]).returns("id" => "ls1", "hmacSecret" => SECRET)

        assert_equal MapEventSource::Webhook.new(id: "ls1", secret: SECRET), Convex.register(@row, url: URL)
        assert_equal Convex::ONLY_STREAM, Convex.confirmation_for(@row, url: URL)

        ConvexApi.any_instance.stubs(:log_streams).returns([ { "logStreamType" => "webhook", "id" => "ls1", "url" => URL, "hmacSecret" => SECRET } ])
        assert_equal MapEventSource::Webhook.new(id: "ls1", secret: SECRET), Convex.register(@row, url: URL)
        assert_nil Convex.confirmation_for(@row, url: URL)

        ConvexApi.any_instance.stubs(:log_streams).returns([ { "logStreamType" => "webhook", "id" => "theirs", "url" => "https://team.example.com" } ])
        assert_match "already sends a webhook log stream", assert_raises(MapEventSource::Refused) { Convex.register(@row, url: URL) }.message
      end

      test "a plan without log streams is a refusal tried again later, and removing one already gone is fine" do
        ConvexApi.any_instance.stubs(:log_streams).returns([])
        ConvexApi.any_instance.stubs(:create_webhook_stream).raises(ConvexApi::Error, "Convex answered 400: Log streams require a Pro plan")
        assert_match "Pro plan", assert_raises(MapEventSource::Refused) { Convex.register(@row, url: URL) }.message

        ConvexApi.any_instance.stubs(:delete_log_stream).with("ls1").raises(ConvexApi::Error, "Convex answered 404: not found")
        assert_nothing_raised { Convex.remove(@row, "ls1") }
        ConvexApi.any_instance.stubs(:delete_log_stream).with("ls1").raises(ConvexApi::Error, "Convex answered 500: oops")
        assert_raises(ConvexApi::Error) { Convex.remove(@row, "ls1") }
      end

      private

      def audit(action, at: 1.minute.ago)
        { "topic" => "audit_log", "timestamp" => (at.to_f * 1000).to_i, "audit_log_action" => action, "audit_log_metadata" => "{}",
          "convex" => { "deployment_name" => "happy-animal-123", "deployment_type" => "prod", "project_name" => "Chat", "project_slug" => "chat" } }
      end
    end
  end
end
