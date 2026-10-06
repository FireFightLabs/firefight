require "test_helper"

module Integrations
  module MapEventSources
    class FlyTest < ActiveSupport::TestCase
      setup do
        @workspace = workspaces(:slack_workspace_one)
        integration = Integration.create!(workspace: @workspace, kind: Integration::KIND_NATIVE, provider: "fly", name: "Fly.io")
        @row = integration.integration_environments.create!
        Packs::Fly.store_credentials!(@row, Packs::Fly::API_TOKEN => "FlyV1 fm2_x")
        @row.store_fields!(Packs::Fly::ORGANIZATION => "acme")
        @apps = [ { "name" => "web", "status" => "deployed" }, { "name" => "api", "status" => "deployed" } ]
        FlyApi.any_instance.stubs(:app_list).with("acme").returns(Pages::Read.new(items: @apps, complete: true))
        stub_machines("web", "started", "2026-10-06T10:00:00Z")
        stub_machines("api", "started", "2026-10-06T10:00:00Z")
        Fly.stubs(:pause)
      end

      test "the first read takes each app's machines and says nothing, and a machine that changed since names its app" do
        first = Fly.poll(@row, since: nil)
        assert_empty first.events
        assert_equal %w[api web], JSON.parse(first.cursor)["apps"].keys.sort

        assert_empty Fly.poll(@row, since: first.cursor).events, "nothing changed"
        stub_machines("web", "stopped", "2026-10-06T10:05:00Z")
        changed = Fly.poll(@row, since: first.cursor).events.sole

        assert_equal [ ResourceMap::Event::UPDATED, ResourceMap::Scope.new(account: "acme", kind: ResourceMap::KIND_SERVICE, external_id: "web") ],
                     [ changed.action, changed.scope ]
      end

      test "a new app is added, one the whole list no longer has is removed, and a list cut short removes nothing" do
        before = Fly.poll(@row, since: nil).cursor
        FlyApi.any_instance.stubs(:app_list).with("acme").returns(Pages::Read.new(items: [ @apps.first, { "name" => "jobs", "status" => "deployed" } ], complete: true))
        stub_machines("jobs", "started", "2026-10-06T10:00:00Z")

        events = Fly.poll(@row, since: before).events
        assert_equal [ [ ResourceMap::Event::ADDED, "jobs" ], [ ResourceMap::Event::REMOVED, "api" ] ], events.map { |event| [ event.action, event.scope.external_id ] }

        FlyApi.any_instance.stubs(:app_list).with("acme").returns(Pages::Read.new(items: [ @apps.first ], complete: false))
        cut = Fly.poll(@row, since: before)
        assert_empty cut.events
        assert_equal %w[api web], JSON.parse(cut.cursor)["apps"].keys.sort
      end

      test "machine lists are read a second apart, an app whose machines could not be read keeps what was known, and a slow down stops the read" do
        Fly.unstub(:pause)
        Fly.expects(:sleep).with(Fly::PACE).once
        before = Fly.poll(@row, since: nil).cursor

        Fly.stubs(:pause)
        FlyApi.any_instance.stubs(:machines).with("web").raises(FlyApi::Error, "Fly answered 500: oops")
        assert_equal JSON.parse(before), JSON.parse(Fly.poll(@row, since: before).cursor)

        FlyApi.any_instance.stubs(:machines).with("web").raises(FlyApi::Error.new("Fly answered 429: slow down").extend(RateLimited))
        assert_raises(FlyApi::Error) { Fly.poll(@row, since: before) }
      end

      private

      def stub_machines(app, state, updated_at)
        machine = { "id" => "m-#{app}", "state" => state, "updated_at" => updated_at, "config" => { "metadata" => { "fly_platform_version" => "v2" } } }
        FlyApi.any_instance.stubs(:machines).with(app).returns([ machine ])
      end
    end
  end
end
