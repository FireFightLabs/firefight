require "test_helper"

module Integrations
  module MapEventSources
    class DigitaloceanTest < ActiveSupport::TestCase
      PACK = Packs::Digitalocean
      # apps_list_events' shape (digitalocean/openapi, models/app_event.yml), cut to the fields read.
      DEPLOYING = { "id" => "ev-1", "type" => "DEPLOYMENT", "created_at" => "2026-10-01T10:00:00Z", "deployment_id" => "dep-2",
                    "deployment" => { "id" => "dep-2", "phase" => "BUILDING" } }.freeze
      SCALED = { "id" => "ev-2", "type" => "AUTOSCALING", "created_at" => "2026-10-01T10:05:00Z", "autoscaling" => { "phase" => "SUCCEEDED" } }.freeze

      setup do
        @workspace = workspaces(:slack_workspace_one)
        integration = Integration.create!(workspace: @workspace, kind: Integration::KIND_NATIVE, provider: PACK::PROVIDER_KEY, name: "DigitalOcean")
        @row = integration.integration_environments.create!
        PACK.store_credentials!(@row, PACK::API_TOKEN => "dop-token")
        %w[app-a app-b].each do |id|
          ResourceMap::Resource.create!(workspace: @workspace, provider: PACK::PROVIDER_KEY, account: "Acme", kind: ResourceMap::KIND_SERVICE, external_id: id,
                                        name: id, integration_environment: @row, first_seen_at: Time.current, last_seen_at: Time.current)
        end
      end

      test "the provider reads each app's events every few minutes rather than being sent them" do
        assert_equal Digitalocean, Provider.for(PACK::PROVIDER_KEY).map_events
        assert Digitalocean.polls?
        assert_not Digitalocean.verify(raw_body: "{}", headers: {}, secret: "x")
      end

      test "the first read only learns each app's events, and a later one reads an app again for an event that is new or moved on" do
        DigitaloceanApi.any_instance.stubs(:events).with("app-a", limit: Digitalocean::PER_APP).returns([ DEPLOYING ])
        DigitaloceanApi.any_instance.stubs(:events).with("app-b", limit: Digitalocean::PER_APP).returns([])
        first = Digitalocean.poll(@row, since: nil)
        assert_empty first.events

        moved = DEPLOYING.merge("deployment" => { "id" => "dep-2", "phase" => "ACTIVE" })
        DigitaloceanApi.any_instance.stubs(:events).with("app-a", limit: Digitalocean::PER_APP).returns([ moved ])
        DigitaloceanApi.any_instance.stubs(:events).with("app-b", limit: Digitalocean::PER_APP).returns([ SCALED ])
        second = Digitalocean.poll(@row, since: first.cursor)

        assert_equal [ "app-a", "app-b" ], second.events.map { |event| event.scope.external_id }
        assert_equal [ ResourceMap::Event::UPDATED ], second.events.map(&:action).uniq
        assert_equal ResourceMap::Scope.new(account: "Acme", kind: ResourceMap::KIND_SERVICE, external_id: "app-b"), second.events.last.scope
        assert_empty Digitalocean.poll(@row, since: second.cursor).events, "nothing moved since"
      end

      test "an app DigitalOcean no longer holds is read again, one it cannot read keeps what it knew, and being asked to slow down stops the read" do
        DigitaloceanApi.any_instance.stubs(:events).returns([ DEPLOYING ])
        cursor = Digitalocean.poll(@row, since: nil).cursor
        DigitaloceanApi.any_instance.stubs(:events).with("app-a", limit: Digitalocean::PER_APP).raises(DigitaloceanApi::NotFound, "DigitalOcean answered 404: not found")
        DigitaloceanApi.any_instance.stubs(:events).with("app-b", limit: Digitalocean::PER_APP).raises(DigitaloceanApi::Error, "DigitalOcean answered 500: oops")

        polled = Digitalocean.poll(@row, since: cursor)

        assert_equal [ "app-a" ], polled.events.map { |event| event.scope.external_id }
        assert_equal [ "app-b" ], JSON.parse(polled.cursor)["apps"].keys
        DigitaloceanApi.any_instance.stubs(:events).raises(DigitaloceanApi::Error.new("DigitalOcean answered 429").extend(Integrations::RateLimited))
        assert_raises(Integrations::RateLimited) { Digitalocean.poll(@row, since: cursor) }
      end

      test "a team with more apps than one read takes is read in turns" do
        DigitaloceanApi.any_instance.stubs(:events).returns([])
        Digitalocean.stubs(:budget).returns(1)

        first = Digitalocean.poll(@row, since: nil)
        assert_equal "app-b", JSON.parse(first.cursor)["next"]
        assert_equal %w[app-a app-b], JSON.parse(Digitalocean.poll(@row, since: first.cursor).cursor)["apps"].keys.sort
      end
    end
  end
end
