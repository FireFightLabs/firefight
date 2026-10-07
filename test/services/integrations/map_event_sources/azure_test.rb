require "test_helper"

module Integrations
  module MapEventSources
    class AzureTest < ActiveSupport::TestCase
      SUBSCRIPTION = "11111111-2222-3333-4444-555555555555".freeze
      GROUP = "/subscriptions/#{SUBSCRIPTION}/resourceGroups/shop/providers".freeze
      WEB_ID = "#{GROUP}/Microsoft.Web/sites/storefront".freeze
      SQL_ID = "#{GROUP}/Microsoft.Sql/servers/shop-sql/databases/orders".freeze

      setup do
        @workspace = workspaces(:slack_workspace_one)
        @integration = Integration.create!(workspace: @workspace, kind: Integration::KIND_NATIVE, provider: "azure", name: "Azure")
        @row = @integration.integration_environments.create!
        Packs::Azure.store_credentials!(@row, Packs::Azure::SECRET => "s3cret")
        @row.store_fields!(Packs::Azure::TENANT => "contoso.onmicrosoft.com", Packs::Azure::CLIENT => "22222222-2222-3333-4444-555555555555",
                           Packs::Azure::SUBSCRIPTION => SUBSCRIPTION)
      end

      test "the first read starts from now and asks Azure nothing" do
        AzureApi.any_instance.expects(:activity_log).never

        travel_to Time.zone.parse("2026-10-06T12:00:00Z") do
          assert_equal MapEventSource::Polled.new(events: [], cursor: { SUBSCRIPTION => "2026-10-06T12:00:00.000000Z" }.to_json), Azure.poll(@row, since: nil)
        end
      end

      test "a read reaches back past the activity log's delay, and each ended operation names the app or database the map keeps" do
        ResourceMap.record!(@row, ResourceMap::Snapshot.new(resources: [
          ResourceMap::Found.new(provider: "azure", account: SUBSCRIPTION, kind: ResourceMap::KIND_SERVICE, external_id: WEB_ID, name: "storefront")
        ]))
        asked = nil
        AzureApi.any_instance.expects(:activity_log).with { |from, to| asked = [ from, to ] }.returns(Pages::Read.new(items: [
          event("e1", "Microsoft.Web/sites/write", WEB_ID.upcase.sub("MICROSOFT.WEB/SITES/STOREFRONT", "Microsoft.Web/sites/STOREFRONT")),
          event("e2", "Microsoft.Web/sites/slots/slotsswap/action", "#{WEB_ID}/slots/staging"),
          event("e3", "Microsoft.Sql/servers/databases/delete", SQL_ID),
          event("e4", "Microsoft.Web/sites/write", WEB_ID, status: "Started"),
          event("e5", "Microsoft.Storage/storageAccounts/write", "#{GROUP}/Microsoft.Storage/storageAccounts/logs"),
          event("e6", "Microsoft.Resources/subscriptions/resourceGroups/delete", "/subscriptions/#{SUBSCRIPTION}/resourceGroups/old"),
          event("e7", "Microsoft.Web/sites/write", "/subscriptions/99999999-2222-3333-4444-555555555555/resourceGroups/x/providers/Microsoft.Web/sites/other")
        ], complete: true))

        polled = travel_to(Time.zone.parse("2026-10-06T12:05:00Z")) { Azure.poll(@row, since: "2026-10-06T12:00:00.000000Z") }

        assert_equal [ Time.zone.parse("2026-10-06T11:30:00Z"), Time.zone.parse("2026-10-06T12:05:00Z") ], asked
        assert_equal({ SUBSCRIPTION => "2026-10-06T12:05:00.000000Z" }, JSON.parse(polled.cursor), "a cursor from before is the subscription's")
        assert_equal %w[e1 e2 e3 e6], polled.events.map(&:id)
        assert_equal [
          [ ResourceMap::KIND_SERVICE, WEB_ID, ResourceMap::Event::UPDATED ],
          [ ResourceMap::KIND_SERVICE, WEB_ID, ResourceMap::Event::UPDATED ],
          [ ResourceMap::KIND_DATABASE, SQL_ID, ResourceMap::Event::REMOVED ]
        ], polled.events.first(3).map { |each| [ each.scope.kind, each.scope.external_id, each.action ] }
        assert polled.events.last.rescope?, "a resource group deleted sweeps the subscription"
        assert_equal Time.iso8601("2026-10-06T12:01:00Z"), polled.events.first.at
      end

      test "each subscription is read from its own cursor, and one the principal cannot read leaves the others read" do
        other = "99999999-2222-3333-4444-555555555555"
        @row.store_fields!(Packs::Azure::TENANT => "contoso.onmicrosoft.com", Packs::Azure::CLIENT => "22222222-2222-3333-4444-555555555555",
                           Packs::Azure::SUBSCRIPTION => [ SUBSCRIPTION, other ])
        refused = stub(activity_log: nil)
        refused.stubs(:activity_log).raises(AzureApi::Error, "Microsoft answered 403: AuthorizationFailed")
        reading = stub(activity_log: Pages::Read.new(items: [ event("e1", "Microsoft.Web/sites/write", WEB_ID) ], complete: true))
        AzureApi.stubs(:new).with(has_entry(subscription: SUBSCRIPTION)).returns(reading)
        AzureApi.stubs(:new).with(has_entry(subscription: other)).returns(refused)
        cursor = { SUBSCRIPTION => "2026-10-06T12:00:00.000000Z", other => "2026-10-06T11:00:00.000000Z" }.to_json

        polled = travel_to(Time.zone.parse("2026-10-06T12:05:00Z")) { Azure.poll(@row, since: cursor) }

        assert_equal %w[e1], polled.events.map(&:id)
        assert_equal({ other => "2026-10-06T11:00:00.000000Z", SUBSCRIPTION => "2026-10-06T12:05:00.000000Z" }, JSON.parse(polled.cursor))
        assert_match "The change log of subscription #{other} could not be read: Microsoft answered 403", polled.error

        AzureApi.stubs(:new).returns(refused)
        assert_raises(AzureApi::Error, "only every subscription failing fails the read") { Azure.poll(@row, since: cursor) }
      end

      private

      def event(id, operation, resource, status: "Succeeded")
        { "eventDataId" => id, "eventTimestamp" => "2026-10-06T12:01:00Z", "operationName" => { "value" => operation },
          "resourceId" => resource, "status" => { "value" => status } }
      end
    end
  end
end
