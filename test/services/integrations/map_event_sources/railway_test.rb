require "test_helper"

module Integrations
  module MapEventSources
    class RailwayTest < ActiveSupport::TestCase
      # The payload Railway's docs show (docs.railway.com/observability/webhooks, Example payload).
      SAMPLE = {
        "type" => "Deployment.failed",
        "details" => { "id" => "8107edff-4b8e-44fc-b43a-04566e847a2a", "source" => "GitHub", "status" => "SUCCESS" },
        "resource" => {
          "workspace" => { "id" => "ws-1", "name" => "Acme" }, "project" => { "id" => "prj-1", "name" => "shop" },
          "environment" => { "id" => "env-prod", "name" => "production", "isEphemeral" => false },
          "service" => { "id" => "svc-web", "name" => "web" }, "deployment" => { "id" => "dep-9" }
        },
        "severity" => "WARNING", "timestamp" => "2025-11-21T23:48:42.311Z"
      }.freeze
      URL = "https://firefight.example.com/api/v1/map_events/token-1".freeze

      setup do
        @workspace = workspaces(:slack_workspace_one)
        @integration = Integration.create!(workspace: @workspace, kind: Integration::KIND_NATIVE, provider: "railway", name: "Railway")
        @row = @integration.integration_environments.create!
        Packs::Railway.store_credentials!(@row, Packs::Railway::API_TOKEN => "rw-token")
        @row.store_fields!(Packs::Railway::PROJECT => "prj-1", Packs::Railway::ENVIRONMENT => "production")
        RailwayApi.any_instance.stubs(:project).with("prj-1").returns("id" => "prj-1", "workspaceId" => "ws-1")
      end

      test "a delivery carrying Firefight's own secret header is Railway's, and one without it or with another is not" do
        body = SAMPLE.to_json

        assert Railway.verify(raw_body: body, headers: { Railway::SECRET_HEADER => "s3cret" }, secret: "s3cret")
        assert_not Railway.verify(raw_body: body, headers: { Railway::SECRET_HEADER => "guess" }, secret: "s3cret")
        assert_not Railway.verify(raw_body: body, headers: {}, secret: "s3cret")
        assert_not Railway.verify(raw_body: body, headers: { Railway::SECRET_HEADER => "" }, secret: nil)
      end

      test "a deployment's status names its service in its project and environment, and the same body is the same event" do
        event = Railway.events(SAMPLE, headers: {}).sole

        assert_equal ResourceMap::Scope.new(account: "prj-1/env-prod", external_id: "svc-web"), event.scope
        assert_equal [ ResourceMap::Event::UPDATED, Time.iso8601("2025-11-21T23:48:42.311Z") ], [ event.action, event.at ]
        assert_equal event.id, Railway.events(JSON.parse(SAMPLE.to_json), headers: {}).sole.id
        assert_not_equal event.id, Railway.events(SAMPLE.merge("type" => "Deployment.deployed"), headers: {}).sole.id
        Railway::EVENTS.each { |type| assert_equal 1, Railway.events(SAMPLE.merge("type" => type), headers: {}).size }
        assert_empty Railway.events(SAMPLE.merge("type" => "VolumeAlert.triggered"), headers: {})
        assert_empty Railway.events(SAMPLE.merge("resource" => SAMPLE["resource"].except("service")), headers: {})
      end

      test "registering adds a webhook with a new secret header, or gives Firefight's own at this address a new one, never touching another" do
        RailwayApi.any_instance.stubs(:notification_rules).with("ws-1", "prj-1")
                  .returns([ { "id" => "rule-theirs", "channels" => [ { "config" => { "type" => "webhook", "url" => "https://example.com/hook" } } ] } ])
        RailwayApi.any_instance.expects(:update_webhook).never
        RailwayApi.any_instance.expects(:create_webhook).with do |workspace, project, url:, events:, headers:|
          [ workspace, project, url, events ] == [ "ws-1", "prj-1", URL, Railway::EVENTS ] && headers[Railway::SECRET_HEADER].size == 64
        end.returns("id" => "rule-1")

        webhook = Railway.register(@row, url: URL)
        assert_equal "rule-1", webhook.id
        assert_equal 64, webhook.secret.size

        RailwayApi.any_instance.unstub(:create_webhook)
        RailwayApi.any_instance.unstub(:update_webhook)
        RailwayApi.any_instance.stubs(:notification_rules).returns([ { "id" => "rule-1", "channels" => [ { "config" => { "type" => "webhook", "url" => URL } } ] } ])
        RailwayApi.any_instance.expects(:create_webhook).never
        RailwayApi.any_instance.expects(:update_webhook).with("rule-1", has_entries(url: URL, events: Railway::EVENTS)).returns("id" => "rule-1")
        again = Railway.register(@row, url: URL)
        assert_equal "rule-1", again.id
        assert_not_equal webhook.secret, again.secret
      end

      test "a refusal is said in Railway's words for a retry tomorrow, and removing takes back only the rule Firefight registered" do
        RailwayApi.any_instance.stubs(:notification_rules).returns([])
        RailwayApi.any_instance.stubs(:create_webhook).raises(RailwayApi::Refused, "Railway refused this: Not Authorized")
        error = assert_raises(MapEventSource::Refused) { Railway.register(@row, url: URL) }
        assert_equal "Railway refused this: Not Authorized", error.message

        RailwayApi.any_instance.expects(:delete_webhook).with("rule-1").returns(true)
        Railway.remove(@row, "rule-1")
        RailwayApi.any_instance.unstub(:delete_webhook)
        RailwayApi.any_instance.stubs(:delete_webhook).raises(RailwayApi::NotFound, "Railway refused this: NotificationRule not found")
        assert_nil Railway.remove(@row, "rule-1")
      end
    end
  end
end
