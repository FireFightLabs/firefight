require "test_helper"

module Integrations
  module MapEventSources
    class NeonTest < ActiveSupport::TestCase
      setup do
        @workspace = workspaces(:slack_workspace_one)
        @integration = Integration.create!(workspace: @workspace, kind: Integration::KIND_MCP, provider: "neon", name: "Neon", settings: { "server_url" => "https://mcp.neon.tech/mcp" })
        @row = @integration.integration_environments.create!
        @integration.tools.create!(name: MapReaders::Neon::LIST_OPERATIONS, enabled: true)
        ResourceMap.record!(@row, ResourceMap::Snapshot.new(resources: [
          ResourceMap::Found.new(provider: "neon", account: "Acme", kind: ResourceMap::KIND_DATABASE, external_id: "shop-123", name: "shop")
        ]))
        @reader = MapReaders::Neon.new
        McpExecutor.stubs(:map_events_reader).with(@row).returns(@reader)
      end

      test "a server without a tool for operations says so, and the first read starts from now" do
        @integration.tools.find_by!(name: MapReaders::Neon::LIST_OPERATIONS).update!(removed_at: Time.current)
        assert_equal Neon::NO_TOOL, assert_raises(Integrations::Error) { Neon.poll(@row, since: nil) }.message

        @integration.tools.find_by!(name: MapReaders::Neon::LIST_OPERATIONS).update!(removed_at: nil)
        @reader.expects(:operations).never
        assert_empty Neon.poll(@row, since: nil).events
      end

      test "an operation that ended names its compute or branch, and upkeep, one still running or one read before names nothing" do
        @reader.stubs(:operations).with("shop-123").returns([
          operation("op-1", "suspend_compute", "finished", 1.minute.ago, endpoint: "ep-cool-1"),
          operation("op-2", "delete_timeline", "finished", 2.minutes.ago, branch: "br-preview-2"),
          operation("op-3", "create_branch", "running", 1.minute.ago, branch: "br-new-3"),
          operation("op-4", "check_availability", "finished", 1.minute.ago),
          operation("op-5", "start_compute", "finished", 1.hour.ago, endpoint: "ep-cool-1")
        ])

        events = Neon.poll(@row, since: 5.minutes.ago.utc.iso8601).events

        assert_equal [ [ "op-1:finished", ResourceMap::Event::UPDATED, ResourceMap::KIND_COMPUTE, "shop-123/ep-cool-1" ],
                       [ "op-2:finished", ResourceMap::Event::REMOVED, ResourceMap::KIND_BRANCH, "shop-123/br-preview-2" ] ],
                     events.map { |event| [ event.id, event.action, event.scope.kind, event.scope.external_id ] }
        assert_equal [ "Acme" ], events.map { |event| event.scope.account }.uniq
      end

      test "a full page of recent operations reads the project again too, and a tool switched off or a refusal is said" do
        @reader.stubs(:operations).returns(Array.new(MapReaders::Neon::OPERATION_LIMIT) { |index| operation("op-#{index}", "apply_config", "finished", 1.minute.ago) })
        assert_includes Neon.poll(@row, since: 5.minutes.ago.utc.iso8601).events.map { |event| event.scope.kind }, ResourceMap::KIND_DATABASE

        @reader.stubs(:operations).returns(nil)
        assert_equal Neon::SWITCHED_OFF, assert_raises(Integrations::Error) { Neon.poll(@row, since: 5.minutes.ago.utc.iso8601) }.message
        @reader.stubs(:operations).raises(RemoteReader::Refused, "Neon refused to list the operations of shop-123: 403 forbidden.")
        assert_raises(MapEventSource::Refused) { Neon.poll(@row, since: 5.minutes.ago.utc.iso8601) }
      end

      private

      def operation(id, action, status, at, endpoint: nil, branch: nil)
        { "id" => id, "project_id" => "shop-123", "action" => action, "status" => status, "updated_at" => at.utc.iso8601, "endpoint_id" => endpoint, "branch_id" => branch }.compact
      end
    end
  end
end
