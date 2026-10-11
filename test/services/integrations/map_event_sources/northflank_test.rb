require "test_helper"

module Integrations
  module MapEventSources
    class NorthflankTest < ActiveSupport::TestCase
      SECRET = "northflank-integration-secret".freeze
      URL = "https://firefight.example.com/api/v1/map_events/token-1".freeze

      setup do
        @workspace = workspaces(:slack_workspace_one)
        @integration = Integration.create!(workspace: @workspace, kind: Integration::KIND_NATIVE, provider: "northflank", name: "Northflank")
        @row = @integration.integration_environments.create!
        Packs::Northflank.store_credentials!(@row, Packs::Northflank::API_TOKEN => "nf-token")
        @row.store_fields!(Packs::Northflank::PROJECT => "firefight")
        @row.give_map_events_token!
      end

      test "a delivery is Northflank's when it carries the integration's own secret in its token header" do
        assert Northflank.verify(raw_body: "{}", headers: { "x-northflank-notification-integration-token" => SECRET }, secret: SECRET)
        assert_not Northflank.verify(raw_body: "{}", headers: { "x-northflank-notification-integration-token" => "another" }, secret: SECRET)
        assert_not Northflank.verify(raw_body: "{}", headers: {}, secret: SECRET)
        assert_not Northflank.verify(raw_body: "{}", headers: { "x-northflank-notification-integration-token" => "" }, secret: nil)
      end

      test "a service, addon or job event names what it is about, by the event id Northflank gives, and anything else names nothing" do
        headers = { "x-northflank-notification-integration-event-id" => "evt-1" }
        build = Northflank.events(delivery("build:success", "service" => { "id" => "web" }, "build" => { "id" => "b-1" }), headers: headers).sole

        assert_equal [ "evt-1", ResourceMap::Event::UPDATED ], [ build.id, build.action ]
        assert_equal ResourceMap::Scope.new(external_id: "web"), build.scope
        assert_equal ResourceMap::Scope.new(kind: ResourceMap::KIND_DATABASE, external_id: "db"),
                     Northflank.events(delivery("addon-backup:start", "addon" => { "id" => "db" }), headers: headers).sole.scope
        assert_equal ResourceMap::Scope.new(kind: ResourceMap::KIND_JOB, external_id: "nightly"),
                     Northflank.events(delivery("trigger:job-run:failure", "job" => { "id" => "nightly" }), headers: headers).sole.scope
        assert_empty Northflank.events(delivery("billing:invoice-paid", "service" => { "id" => "web" }), headers: headers)
        assert_empty Northflank.events(delivery("build:start", "project" => { "id" => "firefight" }), headers: headers)
      end

      test "registering adds a webhook integration for the project's events, deleting only one Firefight left at this same address" do
        NorthflankApi.any_instance.stubs(:notifications).returns(Pages::Read.new(items: [ { "id" => "theirs", "webhook" => "https://example.com" },
                                                                                      { "id" => "old", "webhook" => URL } ], complete: true))
        NorthflankApi.any_instance.expects(:delete_notification).with("old").returns({})
        NorthflankApi.any_instance.expects(:delete_notification).with("theirs").never
        made = nil
        NorthflankApi.any_instance.expects(:create_notification).with { |**options| made = options }.returns("id" => "firefight-live-updates")

        webhook = Northflank.register(@row, url: URL)

        assert_equal [ "firefight-live-updates", made[:secret] ], [ webhook.id, webhook.secret ]
        assert_equal [ URL, [ "firefight" ], "Firefight live updates firefight #{@row.map_events_token.first(6)}" ], [ made[:url], made[:projects], made[:name] ]
        assert_equal Northflank::EVENTS.map { |event| "trigger:#{event}" }, made[:events]
        assert_equal 64, made[:secret].size
      end

      test "a token whose role may not add integrations is refused with the permission it needs, and removing takes one already gone" do
        NorthflankApi.any_instance.stubs(:notifications).raises(NorthflankApi::Refused, "Northflank answered 403: insufficient permissions")
        error = assert_raises(MapEventSource::Refused) { Northflank.register(@row, url: URL) }
        assert_equal "Northflank answered 403: insufficient permissions. #{Northflank::PERMISSION_NOTE}.", error.message

        NorthflankApi.any_instance.expects(:delete_notification).with("firefight-live-updates").raises(NorthflankApi::NotFound, "Northflank answered 404: not found")
        assert_nil Northflank.remove(@row, "firefight-live-updates")
      end

      test "a release flow's run names its pipeline and stage, a template run the project's workflows, and an eviction its service" do
        headers = { "x-northflank-notification-integration-event-id" => "evt-2" }

        assert_equal ResourceMap::Scope.new(kind: ResourceMap::KIND_RELEASE_FLOW, external_id: "shop/production"),
                     Northflank.events(delivery("release-flow-template-run:failure", "pipeline" => { "id" => "shop" }, "stage" => "Production"), headers: headers).sole.scope
        assert_equal ResourceMap::Scope.new(kind: ResourceMap::KIND_PIPELINE, external_id: "shop"),
                     Northflank.events(delivery("release-flow-template-run:start", "pipeline" => { "id" => "shop" }), headers: headers).sole.scope
        assert_equal ResourceMap::Scope.new(kind: ResourceMap::KIND_RELEASE_FLOW),
                     Northflank.events(delivery("release-flow-template-run:success", {}), headers: headers).sole.scope
        assert_equal ResourceMap::Scope.new(kind: ResourceMap::KIND_WORKFLOW), Northflank.events(delivery("template-run:update", "template" => { "id" => "t" }), headers: headers).sole.scope
        assert_equal ResourceMap::Scope.new(external_id: "web"),
                     Northflank.events(delivery("infrastructure:service:container-eviction", "service" => { "id" => "web" }), headers: headers).sole.scope
        assert_includes Northflank::EVENTS, "infrastructure:addon-volume:usage-90-exceeded"
        assert_match "A workflow's run sends nothing, so a watch on one reads it each minute.", Northflank.limits
      end

      test "an integration made before an event joined is registered again, and one that sends them all is left as it is" do
        @row.update!(map_events_webhook_id: "firefight-live-updates")
        every = Northflank::EVENTS.to_h { |event| [ "trigger:#{event}", true ] }
        NorthflankApi.any_instance.stubs(:notification).with("firefight-live-updates").returns("events" => every)
        assert_not Northflank.register_again?(@row, url: URL)

        NorthflankApi.any_instance.stubs(:notification).with("firefight-live-updates").returns("events" => every.except("trigger:release-flow-template-run:failure"))
        assert Northflank.register_again?(@row, url: URL)

        NorthflankApi.any_instance.stubs(:notification).with("firefight-live-updates").raises(NorthflankApi::NotFound, "Northflank answered 404")
        assert Northflank.register_again?(@row, url: URL)
      end

      private

      def delivery(event, data) = { "event" => event, "data" => data }
    end
  end
end
