require "test_helper"

module Integrations
  module MapEventSources
    class ClickhouseTest < ActiveSupport::TestCase
      ORGANIZATION = { "id" => "org-1", "name" => "Acme" }.freeze

      setup do
        @workspace = workspaces(:slack_workspace_one)
        @integration = Integration.create!(workspace: @workspace, kind: Integration::KIND_MCP, provider: "clickhouse", name: "ClickHouse",
                                           settings: { "server_url" => "https://mcp.clickhouse.cloud/mcp" })
        @row = @integration.integration_environments.create!
        @integration.tools.create!(name: MapReaders::Clickhouse::LIST_SERVICES, enabled: true)
        @services = [ service("svc-1", "running"), service("svc-2", "idle") ]
        @pipes = { "svc-1" => [ { "id" => "pipe-9", "state" => "Running" } ], "svc-2" => [] }
        McpExecutor.stubs(:map_events_reader).with(@row).returns(reader)
      end

      test "a server without the services tool says so, and the first read only takes each service's fingerprint" do
        @integration.tools.find_by!(name: MapReaders::Clickhouse::LIST_SERVICES).update!(removed_at: Time.current)
        assert_equal Clickhouse::NO_TOOL, assert_raises(Integrations::Error) { Clickhouse.poll(@row, since: nil) }.message

        @integration.tools.find_by!(name: MapReaders::Clickhouse::LIST_SERVICES).update!(removed_at: nil)
        first = Clickhouse.poll(@row, since: nil)
        assert_empty first.events
        assert_equal %w[svc-1 svc-2], JSON.parse(first.cursor)["services"].keys
        assert_empty Clickhouse.poll(@row, since: first.cursor).events
      end

      test "a service whose state or ClickPipes changed is updated, a new one added and one no longer listed removed" do
        cursor = Clickhouse.poll(@row, since: nil).cursor
        @services = [ service("svc-1", "running"), service("svc-2", "running"), service("svc-3", "provisioning") ]
        @pipes = { "svc-1" => [ { "id" => "pipe-9", "state" => "Failed" } ], "svc-2" => [], "svc-3" => [] }
        polled = Clickhouse.poll(@row, since: cursor)
        events = polled.events

        assert_equal [ [ "svc-1", ResourceMap::Event::UPDATED ], [ "svc-2", ResourceMap::Event::UPDATED ], [ "svc-3", ResourceMap::Event::ADDED ] ],
                     events.map { |event| [ event.scope.external_id, event.action ] }
        assert_equal [ "org-1" ], events.map { |event| event.scope.account }.uniq
        assert_equal [ ResourceMap::KIND_DATABASE ], events.map { |event| event.scope.kind }.uniq

        @services = [ service("svc-1", "running") ]
        gone = Clickhouse.poll(@row, since: polled.cursor).events
        assert_equal [ [ "svc-2", ResourceMap::Event::REMOVED ], [ "svc-3", ResourceMap::Event::REMOVED ] ], gone.map { |event| [ event.scope.external_id, event.action ] }
      end

      test "a ClickPipe its service's whole list no longer has is removed by its own scope" do
        cursor = Clickhouse.poll(@row, since: nil).cursor
        @pipes = { "svc-1" => [], "svc-2" => [] }
        events = Clickhouse.poll(@row, since: cursor).events

        assert_equal [ [ ResourceMap::KIND_DATABASE, "svc-1", ResourceMap::Event::UPDATED ], [ ResourceMap::KIND_PIPELINE, "svc-1/pipe-9", ResourceMap::Event::REMOVED ] ],
                     events.map { |event| [ event.scope.kind, event.scope.external_id, event.action ] }
      end

      test "a ClickPipe list not read keeps the last one, so a removal while it was off is still followed, and a removal's id is stable" do
        cursor = Clickhouse.poll(@row, since: nil).cursor
        @pipes = nil
        off = Clickhouse.poll(@row, since: cursor)
        assert_equal [ "pipe-9" ], JSON.parse(off.cursor).dig("services", "svc-1", "pipes")

        @pipes = { "svc-1" => [], "svc-2" => [] }
        assert_includes Clickhouse.poll(@row, since: off.cursor).events.map { |event| [ event.scope.external_id, event.action ] },
                        [ "svc-1/pipe-9", ResourceMap::Event::REMOVED ]

        @services = [ service("svc-1", "running") ]
        assert_equal Clickhouse.poll(@row, since: cursor).events.map(&:id), Clickhouse.poll(@row, since: cursor).events.map(&:id)
      end

      test "a services list switched off takes nothing as gone, and a refusal is said" do
        cursor = Clickhouse.poll(@row, since: nil).cursor
        @services = nil
        assert_equal Clickhouse::SWITCHED_OFF, assert_raises(Integrations::Error) { Clickhouse.poll(@row, since: cursor) }.message

        @refuse = true
        assert_raises(MapEventSource::Refused) { Clickhouse.poll(@row, since: cursor) }
      end

      private

      def service(id, state) = { "id" => id, "name" => id, "state" => state }

      def reader
        MapReaders::Clickhouse.new do |tool, arguments|
          next { "isError" => true, "content" => [ { "type" => "text", "text" => "Unauthorized" } ] } if @refuse

          case tool
          when MapReaders::Clickhouse::LIST_ORGANIZATIONS then text([ ORGANIZATION ])
          when MapReaders::Clickhouse::LIST_SERVICES then @services && text("result" => @services)
          when MapReaders::Clickhouse::LIST_CLICKPIPES then @pipes && text(@pipes.fetch(arguments["serviceId"], []))
          end
        end
      end

      def text(body) = { "content" => [ { "type" => "text", "text" => body.to_json } ] }
    end
  end
end
