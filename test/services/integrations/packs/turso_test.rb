require "test_helper"

module Integrations
  module Packs
    class TursoTest < ActiveSupport::TestCase
      USAGE = { "total" => { "rows_read" => 1_200_000, "rows_written" => 3400, "storage_bytes" => 52_428_800, "bytes_synced" => 0 },
                "instances" => [ { "uuid" => "i-1", "usage" => { "rows_read" => 1_000_000 } }, { "uuid" => "i-2", "usage" => { "rows_read" => 200_000 } } ] }.freeze

      setup do
        @integration = workspaces(:slack_workspace_one).integrations.create!(kind: Integration::KIND_MCP, provider: "turso", name: "Turso",
                                                                             settings: { "server_url" => "https://mcp.turso.ai/mcp" })
        @row = @integration.integration_environments.create!
        @pack = Turso.new(@integration)
        Credentials.stubs(:headers_for).returns("Authorization" => "Bearer token-1")
      end

      test "usage is read in the organization that holds the database, with the connection's own token" do
        TursoApi.expects(:new).with("Bearer token-1").returns(api = mock("api"))
        api.expects(:organizations).returns([ { "slug" => "personal-1", "name" => "me" }, { "slug" => "acme", "name" => "Acme" } ])
        api.expects(:usage).with("personal-1", "shop", from: "2026-10-01T00:00:00Z", to: nil).raises(TursoApi::NotFound, "Turso answered 404: not found")
        api.expects(:usage).with("acme", "shop", from: "2026-10-01T00:00:00Z", to: nil).returns(USAGE)

        text = usage("database" => "shop", "from" => "2026-10-01T00:00:00Z")
        assert_equal "shop in Acme, from 2026-10-01T00:00:00Z to now: 1,200,000 rows read, 3,400 rows written, 50 MB storage, 0 Bytes synced.\n" \
                     "  instance i-1: 1,000,000 rows read\n  instance i-2: 200,000 rows read", text
      end

      test "a token the Platform API does not take is told how to connect, and a bad time or a missing database is said" do
        TursoApi.any_instance.stubs(:organizations).raises(TursoApi::Refused, "Turso answered 401: invalid token")
        assert_match "Connect Turso again with a Platform API token", refusal("database" => "shop")

        assert_match "from is an ISO 8601 time", refusal("database" => "shop", "from" => "last week")

        TursoApi.any_instance.stubs(:organizations).returns([ { "slug" => "acme" } ])
        TursoApi.any_instance.stubs(:usage).raises(TursoApi::NotFound, "Turso answered 404: not found")
        assert_match "No Turso organization this connection reaches has a database named shop", refusal("database" => "shop")
      end

      private

      def usage(arguments) = @pack.call("database_usage", environment_row: @row, arguments: arguments)

      def refusal(arguments) = assert_raises(Integrations::Error) { usage(arguments) }.message
    end
  end
end
