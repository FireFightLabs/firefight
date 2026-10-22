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

      test "a busy subscription whose log is cut short is swept in full" do
        AzureApi.any_instance.stubs(:activity_log).returns(Pages::Read.new(items: [ event("e1", "Microsoft.Web/sites/write", WEB_ID) ], complete: false))

        polled = travel_to(Time.zone.parse("2026-10-06T12:05:00Z")) { Azure.poll(@row, since: "2026-10-06T12:00:00.000000Z") }

        assert_equal [ "e1", "activity-log-busy #{SUBSCRIPTION} 2026-10-06T12:05:00.000000Z" ], polled.events.map(&:id)
        assert_predicate polled.events.last.scope, :everything?
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

      GRID_PATH = "/subscriptions/#{SUBSCRIPTION}/providers/Microsoft.EventGrid/eventSubscriptions/firefightliveupdates".freeze
      URL = "https://firefight.example.com/api/v1/map_events/token".freeze

      test "turning Event Grid on is a person's choice naming the role, and subscribes each subscription with a secret header once its address is confirmed" do
        assert_match "the app registration Firefight signs in with needs the EventGrid EventSubscription Contributor role on each Azure subscription", Azure.confirmation_for(@row, url: URL)
        assert Azure.registers? && Azure.polls? && Azure.asks_first?

        AzureApi.any_instance.stubs(:get).with("/subscriptions/#{SUBSCRIPTION}/providers/Microsoft.EventGrid", Azure::PROVIDERS_VERSION).returns("registrationState" => "Registered")
        sent = nil
        AzureApi.any_instance.expects(:put).with { |path, version, body| path == GRID_PATH && version == Azure::GRID_VERSION && (sent = body) }.returns({})
        AzureApi.any_instance.stubs(:get).with(GRID_PATH, Azure::GRID_VERSION).returns({ "properties" => { "provisioningState" => "Creating" } })
                                         .then.returns({ "properties" => { "provisioningState" => "Succeeded" } })
        Azure.expects(:pause).with(Azure::GRID_POLL).once

        webhook = Azure.register(@row, url: URL)

        destination = sent.dig("properties", "destination")
        header = destination.dig("properties", "deliveryAttributeMappings").sole
        assert_equal [ "WebHook", URL, Azure::KEY_HEADER, true ], [ destination["endpointType"], destination.dig("properties", "endpointUrl"), header["name"], header.dig("properties", "isSecret") ]
        assert_equal Azure::GRID_EVENTS, sent.dig("properties", "filter", "includedEventTypes")
        assert_equal [ { SUBSCRIPTION => GRID_PATH }.to_json, header.dig("properties", "value"), [ SUBSCRIPTION ] ], [ webhook.id, webhook.secret, webhook.scopes ]
        assert_equal webhook.secret, @row.reload.map_events_secret, "the secret is kept before Event Grid's confirmation arrives"

        AzureApi.any_instance.expects(:delete).with(GRID_PATH, Azure::GRID_VERSION).returns({})
        Azure.remove(@row, webhook.id)
      end

      test "a principal without the role, Event Grid not registered, an address Azure could not reach or any other answer is said in plain words, naming the subscription" do
        @row.store_learned!(@row.learned.merge(ConnectionSettings::SCOPES_LEARNED => [ { "value" => SUBSCRIPTION, "label" => "Production" } ]))
        AzureApi.any_instance.stubs(:get).with("/subscriptions/#{SUBSCRIPTION}/providers/Microsoft.EventGrid", Azure::PROVIDERS_VERSION).returns("registrationState" => "NotRegistered")
        assert_equal "Microsoft.EventGrid is not registered on Production. Register it under the subscription's Resource providers in the Azure portal, " \
                     "then turn instant updates on again.", assert_raises(Integrations::Error) { Azure.register(@row, url: URL) }.message

        AzureApi.any_instance.stubs(:get).with("/subscriptions/#{SUBSCRIPTION}/providers/Microsoft.EventGrid", Azure::PROVIDERS_VERSION).returns("registrationState" => "Registered")
        AzureApi.any_instance.stubs(:delete).returns({})
        AzureApi.any_instance.stubs(:put).raises(AzureApi::Forbidden, "Azure answered 403: The client '2222' does not have authorization")
        refused = assert_raises(Integrations::Error) { Azure.register(@row, url: URL) }
        assert_not refused.is_a?(MapEventSource::Refused), "a refusal never stops the activity log being read"
        assert_equal "The app registration Firefight signs in with does not have the EventGrid EventSubscription Contributor role on Production. " \
                     "Give it that role on the subscription in the Azure portal, then turn instant updates on again.", refused.message

        AzureApi.any_instance.stubs(:put).raises(AzureApi::Error, "Azure answered 500: InternalServerError")
        assert_equal "Azure did not set up instant updates on Production and gave no reason Firefight can act on. Try again in a few minutes.",
                     assert_raises(Integrations::Error) { Azure.register(@row, url: URL) }.message

        AzureApi.any_instance.stubs(:put).returns({})
        AzureApi.any_instance.stubs(:get).with(GRID_PATH, Azure::GRID_VERSION).returns({ "properties" => { "provisioningState" => "Failed" } })
        assert_match "Azure could not reach Firefight's address from Production, so nothing was set up there.",
                     assert_raises(Integrations::Error) { Azure.register(@row, url: URL) }.message
      end

      test "a registration that fails part way takes back what it made in subscriptions it had not covered, and keeps one it had" do
        other = "99999999-2222-3333-4444-555555555555"
        kept = "88888888-2222-3333-4444-555555555555"
        other_path = "/subscriptions/#{other}/providers/Microsoft.EventGrid/eventSubscriptions/firefightliveupdates"
        kept_path = "/subscriptions/#{kept}/providers/Microsoft.EventGrid/eventSubscriptions/firefightliveupdates"
        @row.store_fields!(Packs::Azure::TENANT => "contoso.onmicrosoft.com", Packs::Azure::CLIENT => "22222222-2222-3333-4444-555555555555",
                           Packs::Azure::SUBSCRIPTION => [ kept, SUBSCRIPTION, other ])
        @row.update!(map_events_webhook_id: { kept => kept_path }.to_json)
        AzureApi.any_instance.stubs(:get).with { |path, _version| path.end_with?("/providers/Microsoft.EventGrid") }.returns("registrationState" => "Registered")
        AzureApi.any_instance.stubs(:get).with { |path, _version| path.end_with?("/firefightliveupdates") }.returns({ "properties" => { "provisioningState" => "Succeeded" } })
        AzureApi.any_instance.stubs(:put).with { |path, _version, _body| path == other_path }.raises(AzureApi::Forbidden, "Azure answered 403: no")
        AzureApi.any_instance.stubs(:put).with { |path, _version, _body| path != other_path }.returns({})
        removed = []
        AzureApi.any_instance.stubs(:delete).with { |path, _version| removed << path }.returns({})

        assert_raises(Integrations::Error) { Azure.register(@row, url: URL) }

        assert_equal [ GRID_PATH, other_path ], removed, "the one made and the one that failed are taken back, and the one from before is kept"
      end

      test "a subscription registered before in another case is neither forgotten as gone nor taken back when a later one fails" do
        other = "99999999-2222-3333-4444-555555555555"
        other_path = "/subscriptions/#{other}/providers/Microsoft.EventGrid/eventSubscriptions/firefightliveupdates"
        upper = SUBSCRIPTION.upcase
        @row.store_fields!(Packs::Azure::TENANT => "contoso.onmicrosoft.com", Packs::Azure::CLIENT => "22222222-2222-3333-4444-555555555555",
                           Packs::Azure::SUBSCRIPTION => [ SUBSCRIPTION, other ])
        @row.update!(map_events_webhook_id: { upper => "/subscriptions/#{upper}/providers/Microsoft.EventGrid/eventSubscriptions/firefightliveupdates" }.to_json)
        AzureApi.any_instance.stubs(:get).with { |path, _version| path.end_with?("/providers/Microsoft.EventGrid") }.returns("registrationState" => "Registered")
        AzureApi.any_instance.stubs(:get).with { |path, _version| path.end_with?("/firefightliveupdates") }.returns({ "properties" => { "provisioningState" => "Succeeded" } })
        AzureApi.any_instance.stubs(:put).with { |path, _version, _body| path == other_path }.raises(AzureApi::Forbidden, "Azure answered 403: no")
        AzureApi.any_instance.stubs(:put).with { |path, _version, _body| path != other_path }.returns({})
        removed = []
        AzureApi.any_instance.stubs(:delete).with { |path, _version| removed << path }.returns({})

        assert_raises(Integrations::Error) { Azure.register(@row, url: URL) }

        assert_equal [ other_path ], removed, "only the subscription it had not covered before is taken back"
      end

      test "Event Grid's confirmation is answered with its code, and each delivery with the secret header names the resource it changed" do
        assert Azure.verify(raw_body: "[]", headers: { Azure::KEY_HEADER => "k" }, secret: "k")
        assert_not Azure.verify(raw_body: "[]", headers: { Azure::KEY_HEADER => "x" }, secret: "k")
        assert_not Azure.verify(raw_body: "[]", headers: {}, secret: nil)

        validation = [ { "id" => "v1", "eventType" => Azure::VALIDATION, "data" => { "validationCode" => "512d38b6" } } ]
        assert_equal({ "validationResponse" => "512d38b6" }, Azure.handshake(validation, headers: {}))
        assert_nil Azure.handshake([ grid("g1", "Microsoft.Resources.ResourceWriteSuccess", WEB_ID) ], headers: {})

        events = Azure.events([ grid("g1", "Microsoft.Resources.ResourceWriteSuccess", WEB_ID.sub("resourceGroups", "resourcegroups")),
                                grid("g2", "Microsoft.Resources.ResourceDeleteSuccess", SQL_ID),
                                grid("g3", "Microsoft.Resources.ResourceActionSuccess", "#{WEB_ID}/slots/staging"),
                                grid("g4", "Microsoft.Resources.ResourceWriteSuccess", "#{GROUP}/Microsoft.Storage/storageAccounts/logs"),
                                grid("g5", "Microsoft.Resources.ResourceDeleteSuccess", "/subscriptions/#{SUBSCRIPTION}/resourceGroups/old",
                                     operation: "Microsoft.Resources/subscriptions/resourceGroups/delete") ], headers: {})
        assert_equal [ [ "g1", ResourceMap::Event::UPDATED ], [ "g2", ResourceMap::Event::REMOVED ], [ "g3", ResourceMap::Event::UPDATED ],
                       [ "g5", ResourceMap::Event::RESCOPE ] ], events.map { |event| [ event.id, event.action ] }
        assert_equal [ ResourceMap::KIND_DATABASE, SQL_ID ], [ events.second.scope.kind, events.second.scope.external_id ]
        assert_equal WEB_ID, events.third.scope.external_id, "a change to a slot is about its app"
        assert_match "removes the Event Grid webhook named firefightliveupdates", Azure.turn_off_words
        assert_no_match(/system topic|service principal/, Azure.turn_off_words + Azure::CONFIRMATION)
      end

      def grid(id, type, resource, operation: "x")
        { "id" => id, "eventType" => type, "subject" => resource, "eventTime" => "2026-10-06T12:01:00Z",
          "data" => { "resourceUri" => resource, "operationName" => operation, "status" => "Succeeded" } }
      end

      def event(id, operation, resource, status: "Succeeded")
        { "eventDataId" => id, "eventTimestamp" => "2026-10-06T12:01:00Z", "operationName" => { "value" => operation },
          "resourceId" => resource, "status" => { "value" => status } }
      end
    end
  end
end
